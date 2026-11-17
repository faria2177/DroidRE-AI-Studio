import 'dart:typed_data';
import 'dart:io';

import 'package:archive/archive_io.dart';

/// Loads exactly one bounded, user-selected ZIP member; never writes it to disk.
class PackageBinaryReader {
  const PackageBinaryReader._();

  static Uint8List read({
    required String apkPath,
    required String entryName,
    required int maxBytes,
  }) {
    if (entryName.isEmpty || entryName.length > 1024 || entryName.contains('\\') ||
        entryName.contains(':') || entryName.contains('\u0000') ||
        entryName.split('/').any((s) => s.isEmpty || s == '.' || s == '..')) {
      throw const FormatException('Unsafe ZIP entry path');
    }
    final length = File(apkPath).lengthSync();
    if (length < 22 || length > 1024 * 1024 * 1024 || maxBytes < 1 || maxBytes > 128 * 1024 * 1024) {
      throw const FormatException('Archive or requested member limit exceeded');
    }
    final stream = InputFileStream(apkPath);
    try {
      final archive = ZipDecoder().decodeStream(stream, throwOnError: true);
      if (archive.files.length > 200000) {
        throw const FormatException('Too many ZIP members');
      }
      final matches = archive.files.where((item) => item.name == entryName);
      if (matches.length != 1) {
        throw const FormatException('Member missing or duplicated in APK');
      }
      final file = matches.single;
      if (!file.isFile || file.isSymbolicLink) {
        throw const FormatException('Not a regular binary file');
      }
      if (file.size > maxBytes) {
        throw FormatException('Binary exceeds ${(maxBytes / (1024 * 1024)).round()} MiB inspection limit');
      }
      final bytes = file.readBytes();
      if (bytes == null || bytes.length > maxBytes) {
        throw const FormatException('Cannot read binary within limit');
      }
      return Uint8List.fromList(bytes);
    } finally {
      stream.close();
    }
  }
}
