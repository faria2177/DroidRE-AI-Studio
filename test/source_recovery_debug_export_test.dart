import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:droidre_ai_studio/services/source_recovery_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/debug_info_fixture.dart';

void main() {
  test('exports source positions, parameter names and local lifetimes', () {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('classes.dex', makeDexWithDebugInfo()));
    final bundle = SourceRecoveryBundle.fromArchive(archive);
    expect(bundle.methodsExported, 205);
    expect(bundle.dexFilesVisited, 1);
    expect(bundle.partial, isFalse);

    final zip = ZipDecoder().decodeBytes(bundle.zipBytes, throwOnError: true);
    String read(String path) => utf8.decode(
        zip.files.singleWhere((entry) => entry.name == path).readBytes()!);

    final report = jsonDecode(read('REPORT.json')) as Map<String, dynamic>;
    expect(report['debugMethodsRecovered'], 1);
    expect(report['sourcePositionsRecovered'], 2);
    expect(report['localRangesRecovered'], 3);

    final raw = jsonDecode(
      read('recovered/dex_01/classes/0001/method_debug_info.json'))
      as Map<String, dynamic>;
    final methods = raw['methods'] as List;
    expect(methods, hasLength(205));
    final last = methods.last as Map<String, dynamic>;
    expect(last['method'], 'method204');
    final debug = last['debug'] as Map<String, dynamic>;
    expect(debug['available'], true);
    expect(debug['endSequenceSeen'], true);
    expect(debug['partial'], false);
    expect(debug['positions'], hasLength(2));
    expect(debug['parameterNames'], hasLength(2));
    expect(debug['localRanges'], hasLength(3));
    final first = methods.first as Map<String, dynamic>;
    expect((first['debug'] as Map<String, dynamic>)['available'], false);

    final pseudo = read(
        'source/java_like/dex_01/com/demo/Many_0001.java.txt');
    expect(pseudo, contains('Parameters: method1, method2'));
    expect(pseudo, contains('source line 102'));
    expect(pseudo, contains('Live local variables'));
    expect(pseudo, contains('v0: "method3"'));
    expect(pseudo, contains('not compilable Java'));

    final dalvik = read(
        'source/dalvik/dex_01/com/demo/Many_0001.dalvik.txt');
    expect(dalvik, contains('Source line mapping'));
    expect(dalvik, contains('line 102'));
    expect(dalvik, contains('NOT assemblable Smali'));
  });

  test('does not falsely mark stripped debug data as recovered', () {
    final dex = makeDexWithDebugInfo();
    final view = ByteData.sublistView(dex);
    view.setUint32(8200, 0, Endian.little);
    final stripped = Archive()
      ..addFile(ArchiveFile.bytes('classes.dex', dex));
    final bundle = SourceRecoveryBundle.fromArchive(stripped);
    final zip = ZipDecoder().decodeBytes(bundle.zipBytes, throwOnError: true);
    final json = utf8.decode(zip.files.singleWhere(
        (file) => file.name == 'REPORT.json').readBytes()!);
    final report = jsonDecode(json) as Map<String, dynamic>;
    expect(report['debugMethodsRecovered'], 0);
    expect(report['sourcePositionsRecovered'], 0);
  });

  test('bad debug sequence marks partial without dropping methods', () {
    final input = Archive()..addFile(ArchiveFile.bytes(
        'classes.dex', makeDexWithDebugInfo(badAddress: true)));
    final bundle = SourceRecoveryBundle.fromArchive(input);
    expect(bundle.methodsExported, 205);
    expect(bundle.partial, isTrue);
    expect(bundle.warnings.join(' '), contains('debug information'));
  });
}
