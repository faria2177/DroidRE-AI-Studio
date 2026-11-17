import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

/// The desktop picker may return only the selected path, not write bytes.
/// Android keeps using the document-provider save operation.
class LocalExportService {
  const LocalExportService._();

  static Future<String?> saveFile({
    required String dialogTitle,
    required String fileName,
    required Uint8List bytes,
    String? protectedPath,
  }) async {
    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (!desktop) {
      return FilePicker.platform.saveFile(
          dialogTitle: dialogTitle, fileName: fileName, bytes: bytes);
    }
    final selection = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle, fileName: fileName);
    if (selection == null) {
      return null;
    }
    await writeDesktopFile(selection, bytes, protectedPath: protectedPath);
    return selection;
  }

  static Future<void> writeDesktopFile(String selection, Uint8List bytes,
      {String? protectedPath}) async {
    final target = File(selection);
    if (protectedPath != null) {
      final original = await File(protectedPath).resolveSymbolicLinks();
      final parent = await target.parent.resolveSymbolicLinks();
      final candidate = await target.exists()
          ? await target.resolveSymbolicLinks()
          : p.join(parent, p.basename(selection));
      if (p.equals(original, candidate)) {
        throw const FileSystemException('Cannot overwrite the imported APK');
      }
      if (await FileSystemEntity.type(selection, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FileSystemException('Select a new unsigned APK filename');
      }
    }
    await target.writeAsBytes(bytes, flush: true);
  }
}
