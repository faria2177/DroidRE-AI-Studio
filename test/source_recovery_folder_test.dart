import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:droidre_ai_studio/models/apk_report.dart';
import 'package:droidre_ai_studio/services/source_recovery_bundle.dart';
import 'package:droidre_ai_studio/services/source_recovery_folder_service.dart';
import 'package:flutter_test/flutter_test.dart';

SourceRecoveryResult sampleBundle({String? rawPath}) {
  final zip = Archive()
    ..addFile(ArchiveFile.string('README.md', 'Read-only source recovery'))
    ..addFile(ArchiveFile.string(
        rawPath ?? 'source/java_like/dex_01/com/demo/Main_0001.java.txt',
        '// Decompiled Java-like pseudocode, not compilable'))
    ..addFile(ArchiveFile.string(
        'source/dalvik/dex_01/com/demo/Main_0001.dalvik.txt',
        '# Read-only decoded Dalvik text'))
    ..addFile(ArchiveFile.string('REPORT.json', '{"partial":false}'));
  return SourceRecoveryResult(
    zipBytes: Uint8List.fromList(ZipEncoder().encode(zip)),
    dexFilesVisited: 1,
    classesExported: 1,
    methodsExported: 4,
    warnings: const [],
    partial: false,
  );
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('droidre_generated_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('creates package-based folders with individual source files', () async {
    final result = await SourceRecoveryFolderService.writeBundle(
      root: root,
      projectId: 'project-101',
      packageName: 'com.demo.app',
      bundle: sampleBundle(),
    );
    expect(result.folderPath, contains('com_demo_app_project-101'));
    expect(result.filesWritten, 4);
    expect(result.classesExported, 1);
    final paths = await SourceRecoveryFolderService.listRelativeFiles(
        result.folderPath);
    expect(paths, contains('REPORT.json'));
    expect(paths,
        contains('source/java_like/dex_01/com/demo/Main_0001.java.txt'));
    expect(paths,
        contains('source/dalvik/dex_01/com/demo/Main_0001.dalvik.txt'));

    final preview = await SourceRecoveryFolderService.previewFile(
        result.folderPath,
        'source/java_like/dex_01/com/demo/Main_0001.java.txt');
    expect(preview, contains('not compilable'));
    expect(await File('${result.folderPath}/REPORT.json').exists(), isTrue);
  });

  test('does not overwrite existing generated directory', () async {
    final result = await SourceRecoveryFolderService.writeBundle(
      root: root,
      projectId: '1',
      packageName: 'app',
      bundle: sampleBundle(),
    );
    await File('${result.folderPath}/README.md').writeAsString('user edit');
    await expectLater(
      SourceRecoveryFolderService.writeBundle(
        root: root,
        projectId: '1',
        packageName: 'app',
        bundle: sampleBundle(),
      ), throwsA(isA<FileSystemException>()),
    );
    expect(await File('${result.folderPath}/README.md').readAsString(),
        'user edit');
  });

  test('rejects traversal and cleans intermediate directories', () async {
    await expectLater(
      SourceRecoveryFolderService.writeBundle(
        root: root,
        projectId: 'bad',
        packageName: 'app',
        bundle: sampleBundle(rawPath: '../outside.txt'),
      ), throwsFormatException,
    );
    final members = await root.list().toList();
    expect(members, isEmpty);
  });

  test('Windows reserved filenames are rejected if running on Windows', () async {
    if (!Platform.isWindows) {
      return;
    }
    await expectLater(SourceRecoveryFolderService.writeBundle(
        root: root, projectId: 'reserved', packageName: 'app',
        bundle: sampleBundle(rawPath: 'source/CON.txt')), throwsFormatException);
    expect(await root.list().toList(), isEmpty);
  });

  test('file preview rejects path traversal', () async {
    final result = await SourceRecoveryFolderService.writeBundle(
      root: root,
      projectId: '1',
      packageName: 'app',
      bundle: sampleBundle(),
    );
    await expectLater(
      SourceRecoveryFolderService.previewFile(
        result.folderPath, '../../private.txt'),
      throwsFormatException,
    );
  });

  test('project index preserves generated folder location', () {
    final report = ApkReport.fromJson({
      'id': '11',
      'fileName': 'demo.apk',
      'localPath': '/tmp/demo.apk',
      'sha256': 'abc',
    });
    final generated = report.withRecovery(
      folderPath: '/storage/emulated/0/Android/data/demo/files/code',
      partial: true,
      fileCount: 24,
    );
    final restored = ApkReport.fromJson(generated.toJson());
    expect(restored.recoveredFolderPath, generated.recoveredFolderPath);
    expect(restored.recoveryPartial, isTrue);
    expect(restored.recoveredFileCount, 24);
    expect(restored.id, '11');
  });
}
