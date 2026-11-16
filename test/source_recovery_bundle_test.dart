import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:droidre_ai_studio/services/source_recovery_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/many_methods_fixture.dart';

Archive createSource({
  bool includeDex = true,
  bool includeManifest = true,
}) {
  final source = Archive();
  if (includeDex) {
    source.addFile(ArchiveFile.bytes('classes.dex', makeManyMethodsDex()));
  }
  if (includeManifest) {
    source.addFile(ArchiveFile.string('AndroidManifest.xml',
        '<manifest package="com.example.fixture"/>'));
  }
  return source;
}

void main() {
  test('exports class and beyond-200 method pages with explicit warnings', () {
    final bundle = SourceRecoveryBundle.fromArchive(
      createSource(), packageName: 'com.example.fixture',
      sourceSha256: 'abc123',
    );
    expect(bundle.dexFilesVisited, 1);
    expect(bundle.classesExported, 1);
    expect(bundle.methodsExported, 205);
    expect(bundle.partial, isFalse);

    final output = ZipDecoder().decodeBytes(bundle.zipBytes,
        throwOnError: true);
    final names = output.files.map((file) => file.name).toSet();
    expect(names, contains('README.md'));
    expect(names, contains('REPORT.json'));
    expect(names, contains('recovered/dex_01/classes/0001/dalvik.txt'));
    expect(names, contains('recovered/dex_01/classes/0001/java_like.txt'));
    expect(names, contains('source/java_like/dex_01/com/demo/Many_0001.java.txt'));
    expect(names, contains('source/dalvik/dex_01/com/demo/Many_0001.dalvik.txt'));

    expect(names, contains('recovered/dex_01/classes/0001/methods.txt'));
    expect(names, contains('resources/raw/0001.bin'));

    String content(String path) {
      final file = output.files.singleWhere((item) => item.name == path);
      return utf8.decode(file.readBytes()!);
    }
    expect(content('README.md'), contains('NON-COMPILABLE'));
    expect(content('README.md'), contains('NON-ASSEMBLABLE'));
    expect(content('recovered/dex_01/classes/0001/methods.txt'),
        contains('method204'));
    expect(content('recovered/dex_01/classes/0001/java_like.txt'),
        contains('Java-like pseudo statements are not compilable Java'));
    final report = jsonDecode(content('REPORT.json')) as Map<String, dynamic>;
    expect(report['methodsExported'], 205);
    expect(report['sourceSha256'], 'abc123');
    expect(report['partial'], false);
  });

  test('skips oversized resources with visible partial report', () {
    final source = createSource(includeDex: false);
    source.addFile(ArchiveFile.bytes(
        'assets/huge.bin',
        Uint8List(SourceRecoveryBundle.maxSingleResource + 1)));
    final bundle = SourceRecoveryBundle.fromArchive(source);
    expect(bundle.partial, isTrue);
    expect(bundle.warnings.join(' '), contains('oversized'));
    expect(bundle.warnings.join(' '), contains('No classes.dex'));
    final zip = ZipDecoder().decodeBytes(bundle.zipBytes, throwOnError: true);
    expect(zip.files.any((entry) => entry.name == 'REPORT.json'), isTrue);
  });

  test('rejects unsafe and duplicate archive member paths', () {
    final unsafe = Archive()
      ..addFile(ArchiveFile.string('../outside.txt', 'x'));
    expect(() => SourceRecoveryBundle.fromArchive(unsafe),
        throwsFormatException);

    final duplicate = Archive()
      ..addFile(ArchiveFile.string('res\\layout\\main.xml', 'a'))
      ..addFile(ArchiveFile.string('res/layout/main.xml', 'b'));
    expect(() => SourceRecoveryBundle.fromArchive(duplicate),
        throwsFormatException);
  });

  test('does not export fake rebuildable Smali or Java files', () {
    final bundle = SourceRecoveryBundle.fromArchive(createSource());
    final zip = ZipDecoder().decodeBytes(bundle.zipBytes,
        throwOnError: true);
    expect(zip.files.where((file) => file.name.endsWith('.smali')),
        isEmpty);
    expect(zip.files.where((file) => file.name.endsWith('.java')),
        isEmpty);
    expect(zip.files.where((file) =>
        file.name.endsWith('AndroidManifest.xml')), isEmpty);
  });

  test('DEX count is bounded and skipped DEX files are reported', () {
    final dex = makeManyMethodsDex();
    final source = Archive()
      ..addFile(ArchiveFile.bytes('classes.dex', dex))
      ..addFile(ArchiveFile.bytes('classes2.dex', dex))
      ..addFile(ArchiveFile.bytes('classes3.dex', dex))
      ..addFile(ArchiveFile.bytes('classes4.dex', dex));
    final bundle = SourceRecoveryBundle.fromArchive(source);
    expect(bundle.dexFilesVisited, 2); // Method limit of 400 is reached.
    expect(bundle.methodsExported, SourceRecoveryBundle.maxMethods);
    expect(bundle.partial, isTrue);
    expect(bundle.warnings.join(' '), contains('first 3'));
  });
}
