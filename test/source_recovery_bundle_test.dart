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

  test('cursor validation rejects invalid syntax and out-of-range positions', () {
    expect(() => SourceRecoveryCursor.parse('-1:0:0'), throwsFormatException);
    expect(() => SourceRecoveryCursor.parse('1:2'), throwsFormatException);
    expect(() => SourceRecoveryBundle.fromArchive(createSource(),
        cursor: const SourceRecoveryCursor(dexIndex: 1)), throwsFormatException);
    expect(() => SourceRecoveryBundle.fromArchive(createSource(),
        cursor: const SourceRecoveryCursor(classIndex: 1)), throwsFormatException);
    expect(() => SourceRecoveryBundle.fromArchive(createSource(),
        cursor: const SourceRecoveryCursor(methodIndex: 205)), throwsFormatException);
    expect(SourceRecoveryCursor.parse('2:3:4').token, '2:3:4');
  });

  test('pagination resumes within a class without losing later DEX methods', () {
    final dex = makeManyMethodsDex();
    final source = Archive();
    for (final name in ['classes10.dex', 'classes3.dex', 'classes.dex', 'classes2.dex']) {
      source.addFile(ArchiveFile.bytes(name, dex));
    }
    final first = SourceRecoveryBundle.fromArchive(source);
    expect(first.nextCursor?.token, '1:0:195');
    final second = SourceRecoveryBundle.fromArchive(source,
        cursor: SourceRecoveryCursor.parse(first.nextCursor!.token));
    expect(second.methodsExported, 400);
    expect(second.nextCursor?.token, '3:0:185');
    final last = SourceRecoveryBundle.fromArchive(source, cursor: second.nextCursor!);
    expect(last.methodsExported, 20);
    expect(last.nextCursor, isNull);
    expect(first.methodsExported + second.methodsExported + last.methodsExported, 820);
    final zip = ZipDecoder().decodeBytes(second.zipBytes, throwOnError: true);
    final report = jsonDecode(utf8.decode(zip.files.singleWhere(
        (file) => file.name == 'REPORT.json').readBytes()!)) as Map<String, dynamic>;
    expect(report['dexOrder'], ['classes.dex', 'classes2.dex', 'classes3.dex', 'classes10.dex']);
    expect(report['startCursor']['token'], '1:0:195');
    expect(report['nextCursor']['token'], '3:0:185');
    final entries = report['entries'] as List;
    final resumed = entries.first as Map<String, dynamic>;
    expect(resumed['firstMethodOrdinal'], 195);
    expect(resumed['processedMethods'], 10);
    expect(resumed['dex'], 'classes2.dex');
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
