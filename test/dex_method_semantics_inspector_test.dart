import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:droidre_ai_studio/services/dex_inspector.dart';
import 'package:droidre_ai_studio/services/dex_method_pager.dart';
import 'package:droidre_ai_studio/services/dex_method_semantics_inspector.dart';
import 'package:droidre_ai_studio/services/source_recovery_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/method_semantics_fixture.dart';

void main() {
  test('decodes typed and catch-all handlers with bounded code addresses', () {
    final dex = makeDexWithTryAndReferences();
    final cls = DexInspector.inspectBytes(dex).classes.single;
    final method = DexMethodPager.loadBytes(dex, cls, start: 204).single;
    expect(method.name, 'method204');
    expect(method.codeOffset, 8192);
    final semantic = DexMethodSemanticsInspector.inspectBytes(dex, method);
    expect(semantic.partial, isFalse);
    expect(semantic.tries, hasLength(1));
    final region = semantic.tries.single;
    expect(region.startAddress, 0);
    expect(region.endAddress, 5);
    expect(region.handlers, hasLength(2));
    expect(region.handlers.first.typeDescriptor, 'Lcom/demo/Many;');
    expect(region.handlers.first.address, 5);
    expect(region.handlers.last.typeDescriptor, isNull);
    expect(region.handlers.last.address, 5);
  });

  test('records instruction offsets and string/method pool links', () {
    final dex = makeDexWithTryAndReferences();
    final cls = DexInspector.inspectBytes(dex).classes.single;
    final method = DexMethodPager.loadBytes(dex, cls, start: 204).single;
    final semantic = DexMethodSemanticsInspector.inspectBytes(dex, method);
    expect(semantic.references, hasLength(2));
    expect(semantic.references.first.kind, 'string');
    expect(semantic.references.first.codeUnitOffset, 0);
    expect(semantic.references.first.index, 1);
    expect(semantic.references.first.label, contains('method0'));
    expect(semantic.references.last.kind, 'method');
    expect(semantic.references.last.codeUnitOffset, 2);
    expect(semantic.references.last.index, 200);
    expect(semantic.references.last.label, contains('method200'));
    expect(semantic.references.last.resolved, isTrue);
    expect(semantic.toJson()['poolReferences'], hasLength(2));
  });

  test('invalid handler offset is partial, references are still decoded', () {
    final dex = makeDexWithTryAndReferences(brokenHandlerOffset: true);
    final cls = DexInspector.inspectBytes(dex).classes.single;
    final method = DexMethodPager.loadBytes(dex, cls, start: 204).single;
    final semantic = DexMethodSemanticsInspector.inspectBytes(dex, method);
    expect(semantic.partial, isTrue);
    expect(semantic.tries, isEmpty);
    expect(semantic.references, hasLength(2));
    expect(semantic.warnings.join(' '), contains('handler offset'));
  });

  test('out-of-range exception handler remains a warning', () {
    final dex = makeDexWithTryAndReferences(brokenCatchAddress: true);
    final cls = DexInspector.inspectBytes(dex).classes.single;
    final method = DexMethodPager.loadBytes(dex, cls, start: 204).single;
    final semantic = DexMethodSemanticsInspector.inspectBytes(dex, method);
    expect(semantic.partial, isTrue);
    expect(semantic.tries, isEmpty);
    expect(semantic.references, hasLength(2));
    expect(semantic.warnings.join(' '), contains('outside method'));
  });

  test('unknown Dalvik opcode does not discard independent try metadata', () {
    final dex = makeDexWithTryAndReferences(brokenOpcode: true);
    final cls = DexInspector.inspectBytes(dex).classes.single;
    final method = DexMethodPager.loadBytes(dex, cls, start: 204).single;
    final semantic = DexMethodSemanticsInspector.inspectBytes(dex, method);
    expect(semantic.partial, isTrue);
    expect(semantic.tries, hasLength(1));
    expect(semantic.references, isEmpty);
    expect(semantic.warnings.join(' '), contains('reference decoding'));
  });

  test('monitor operations are not mistaken for type references', () {
    final dex = makeDexWithTryAndReferences();
    final view = ByteData.sublistView(dex);
    for (final (index, word) in <(int, int)>[
      (0, 0x001d), // monitor-enter v0
      (1, 0x001e), // monitor-exit v0
      (2, 0x000e), // return-void
      (3, 0), (4, 0), (5, 0),
    ]) {
      view.setUint16(8192 + 16 + index * 2, word, Endian.little);
    }
    final cls = DexInspector.inspectBytes(dex).classes.single;
    final method = DexMethodPager.loadBytes(dex, cls, start: 204).single;
    final report = DexMethodSemanticsInspector.inspectBytes(dex, method);
    expect(report.references, isEmpty);
    expect(report.tries, hasLength(1));
  });

  test('invoke-polymorphic extracts both method and prototype IDs', () {
    final dex = makeDexWithTryAndReferences();
    final view = ByteData.sublistView(dex);
    for (final (index, word) in <(int, int)>[
      (0, 0x10fa), (1, 1), (2, 0), (3, 0),
      (4, 0x000e), (5, 0x000e),
    ]) {
      view.setUint16(8192 + 16 + index * 2, word, Endian.little);
    }
    final cls = DexInspector.inspectBytes(dex).classes.single;
    final method = DexMethodPager.loadBytes(dex, cls, start: 204).single;
    final report = DexMethodSemanticsInspector.inspectBytes(dex, method);
    expect(report.references.map((entry) => entry.kind),
        ['method', 'proto']);
    expect(report.references.first.index, 1);
    expect(report.references.last.index, 0);
    expect(report.references.last.label, contains('Lcom/demo/Many;'));
  });

  test('abstract method has no code semantics', () {
    final dex = makeDexWithTryAndReferences();
    final cls = DexInspector.inspectBytes(dex).classes.single;
    final method = DexMethodPager.loadBytes(dex, cls, start: 0).first;
    expect(method.codeOffset, 0);
    final semantic = DexMethodSemanticsInspector.inspectBytes(dex, method);
    expect(semantic.partial, isFalse);
    expect(semantic.tries, isEmpty);
    expect(semantic.references, isEmpty);
  });

  test('exported project folder contains per-method semantic JSON', () {
    final apk = Archive()
      ..addFile(ArchiveFile.bytes('classes.dex',
          makeDexWithTryAndReferences()));
    final bundle = SourceRecoveryBundle.fromArchive(apk);
    final zip = ZipDecoder().decodeBytes(bundle.zipBytes, throwOnError: true);
    String read(String name) => utf8.decode(
      zip.files.singleWhere((f) => f.name == name).readBytes()!);
    final report = jsonDecode(read('REPORT.json')) as Map<String, dynamic>;
    expect(report['methodsExported'], 205);
    expect(report['tryRegionsExported'], 1);
    expect(report['referencesExported'], 2);
    final decoded = jsonDecode(
      read('recovered/dex_01/classes/0001/method_semantics.json'))
        as Map<String, dynamic>;
    final methods = decoded['methods'] as List;
    expect(methods, hasLength(205));
    final last = methods.last as Map<String, dynamic>;
    expect(last['method'], 'method204');
    final semantics = last['analysis'] as Map<String, dynamic>;
    expect(semantics['tryRegions'], hasLength(1));
    expect(semantics['poolReferences'], hasLength(2));
    expect(read('source/dalvik/dex_01/com/demo/Many_0001.dalvik.txt'),
      contains('catch Lcom/demo/Many;'));
  });
}
