import 'dart:typed_data';

import 'package:droidre_ai_studio/services/dex_debug_info_inspector.dart';
import 'package:droidre_ai_studio/services/dex_inspector.dart';
import 'package:droidre_ai_studio/services/dex_method_pager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/debug_info_fixture.dart';
import 'support/many_methods_fixture.dart';

DexMethodSummary finalMethod(Uint8List dex) {
  final klass = DexInspector.inspectBytes(dex).classes.single;
  return DexMethodPager.loadBytes(dex, klass, start: 204).single;
}

void main() {
  test('decodes parameter names, line positions and live local ranges', () {
    final dex = makeDexWithDebugInfo();
    final debug = DexDebugInfoInspector.inspectBytes(
        dex, finalMethod(dex), defaultSourceFile: 'Many.java');
    expect(debug.available, isTrue);
    expect(debug.debugInfoOffset, 9200);
    expect(debug.sequenceEnded, isTrue);
    expect(debug.partial, isFalse);
    expect(debug.lineStart, 100);
    expect(debug.parameters.map((p) => p.name), ['method1', 'method2']);
    expect(debug.positions, hasLength(2));
    expect(debug.positions.map((p) => p.address), [1, 4]);
    expect(debug.positions.map((p) => p.line), [102, 102]);
    expect(debug.positions.first.sourceFile, 'Many.java');
    expect(debug.positions.first.prologueEnd, isTrue);
    expect(debug.positions.first.epilogueBegin, isFalse);
    expect(debug.positions.last.sourceFile, 'method6');
    expect(debug.positions.last.epilogueBegin, isTrue);
    expect(debug.locals, hasLength(3));

    final first = debug.locals.singleWhere(
        (item) => item.register == 0 && !item.restarted);
    expect(first.name, 'method3');
    expect(first.typeDescriptor, 'Lcom/demo/Many;');
    expect(first.startAddress, 0);
    expect(first.endAddressExclusive, 2);

    final extended = debug.locals.singleWhere((item) => item.register == 1);
    expect(extended.name, 'method4');
    expect(extended.signature, 'method5');
    expect(extended.startAddress, 1);
    expect(extended.endAddressExclusive, 6);

    final restarted = debug.locals.singleWhere(
        (item) => item.register == 0 && item.restarted);
    expect(restarted.startAddress, 3);
    expect(restarted.endAddressExclusive, 6);

    final json = debug.toJson();
    expect(json['lineStart'], 100);
    expect(json['positions'], hasLength(2));
    expect(json['localRanges'], hasLength(3));
    expect(json['note'], contains('do not reconstruct original'));
  });

  test('stripped debug information is absent, not a fake source map', () {
    final dex = makeManyMethodsDex();
    final method = finalMethod(dex);
    expect(method.codeOffset, 0);
    final debug = DexDebugInfoInspector.inspectBytes(dex, method);
    expect(debug.available, isFalse);
    expect(debug.partial, isFalse);
    expect(debug.positions, isEmpty);
    expect(debug.locals, isEmpty);
    expect(debug.parameters, isEmpty);
  });

  test('mismatched debug parameter list reports partial coverage', () {
    final dex = makeDexWithDebugInfo(badParameterCount: true);
    final report = DexDebugInfoInspector.inspectBytes(dex, finalMethod(dex));
    expect(report.available, isTrue);
    expect(report.partial, isTrue);
    expect(report.parameters, hasLength(1));
    expect(report.warnings.join(' '), contains('prototype count'));
    expect(report.sequenceEnded, isTrue);
  });

  test('invalid local register preserves partial metadata', () {
    final dex = makeDexWithDebugInfo(badRegister: true);
    final report = DexDebugInfoInspector.inspectBytes(dex, finalMethod(dex));
    expect(report.available, isTrue);
    expect(report.partial, isTrue);
    expect(report.sequenceEnded, isFalse);
    expect(report.warnings.join(' '), contains('register is outside'));
    expect(report.parameters, hasLength(2));
  });

  test('unresolved string index is reported, never invented', () {
    final dex = makeDexWithDebugInfo(brokenStringIndex: true);
    final report = DexDebugInfoInspector.inspectBytes(dex, finalMethod(dex));
    expect(report.partial, isTrue);
    expect(report.warnings.join(' '), contains('string index'));
    expect(report.sequenceEnded, isFalse);
  });

  test('PC beyond method bounds stops debug decoding', () {
    final dex = makeDexWithDebugInfo(badAddress: true);
    final report = DexDebugInfoInspector.inspectBytes(dex, finalMethod(dex));
    expect(report.partial, isTrue);
    expect(report.sequenceEnded, isFalse);
    expect(report.positions, hasLength(1));
    expect(report.warnings.join(' '), contains('past method'));
    expect(report.locals.any((item) =>
        item.endAddressExclusive == null), isTrue);
  });

  test('missing END_SEQUENCE marks partial and open-ended locals', () {
    final dex = makeDexWithDebugInfo(omitEnd: true);
    final report = DexDebugInfoInspector.inspectBytes(dex, finalMethod(dex));
    expect(report.partial, isTrue);
    expect(report.sequenceEnded, isFalse);
    expect(report.locals.where((item) =>
        item.endAddressExclusive == null), isNotEmpty);
  });
}
