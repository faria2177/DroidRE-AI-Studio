import 'dart:io';

import 'package:archive/archive.dart';
import 'package:droidre_ai_studio/services/apk_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('droidre_test_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('inventories a real ZIP file containing APK-style entries', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string(
        'AndroidManifest.xml',
        '<manifest package="com.demo.sample" android:versionCode="3"/>',
      ))
      ..addFile(ArchiveFile.bytes('classes.dex', [100, 101, 120, 10]))
      ..addFile(ArchiveFile.bytes('classes2.dex', [100, 101, 120, 10]))
      ..addFile(ArchiveFile.bytes('lib/arm64-v8a/libsample.so', [127, 69, 76, 70]));
    final path = '${directory.path}/demo.apk';
    await File(path).writeAsBytes(ZipEncoder().encode(archive));

    final result = await ApkAnalyzer.inspect(
      path: path,
      displayName: 'demo.apk',
      id: 'test',
    );

    expect(result.entryCount, 4);
    expect(result.dexCount, 2);
    expect(result.nativeCount, 1);
    expect(result.manifest.packageName, 'com.demo.sample');
    expect(result.sha256, hasLength(64));
  });

  test('rejects a malformed archive', () async {
    final path = '${directory.path}/bad.apk';
    await File(path).writeAsString('not a ZIP archive');
    expect(
      () => ApkAnalyzer.inspect(path: path, displayName: 'bad.apk', id: 'bad'),
      throwsA(isA<Exception>()),
    );
  });
}
