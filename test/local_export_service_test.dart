import 'dart:io';
import 'dart:typed_data';

import 'package:droidre_ai_studio/services/local_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop export writes bytes and protects the source APK', () async {
    final root = await Directory.systemTemp.createTemp('droidre_export_');
    try {
      final original = File('${root.path}/original.apk');
      await original.writeAsBytes([1, 2]);
      final output = File('${root.path}/new.apk');
      await LocalExportService.writeDesktopFile(output.path,
          Uint8List.fromList([3, 4]), protectedPath: original.path);
      expect(await output.readAsBytes(), [3, 4]);
      await expectLater(LocalExportService.writeDesktopFile(original.path,
          Uint8List.fromList([5]), protectedPath: original.path),
          throwsA(isA<FileSystemException>()));
      await expectLater(LocalExportService.writeDesktopFile(output.path,
          Uint8List.fromList([5]), protectedPath: original.path),
          throwsA(isA<FileSystemException>()));
      expect(await original.readAsBytes(), [1, 2]);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
