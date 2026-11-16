import 'dart:typed_data';

import 'package:droidre_ai_studio/services/dex_inspector.dart';
import 'package:droidre_ai_studio/services/dex_method_pager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/many_methods_fixture.dart';

void main() {
  test('loads methods after the initial 200-method preview', () {
    final bytes = makeManyMethodsDex();
    final klass = DexInspector.inspectBytes(bytes).classes.single;
    expect(klass.classDefIndex, 0);
    expect(klass.methodCount, 205);
    expect(klass.details, hasLength(200));

    final next = DexMethodPager.loadBytes(bytes, klass, start: 200, limit: 3);
    expect(next.map((method) => method.name).toList(), [
      'method200', 'method201', 'method202',
    ]);
    expect(next.map((method) => method.methodIdIndex).toList(), [200, 201, 202]);
    expect(next.first.ownerName, 'com.demo.Many');
    expect(DexMethodPager.loadBytes(bytes, klass, start: 204), hasLength(1));
    expect(DexMethodPager.loadBytes(bytes, klass, start: 205), isEmpty);
  });

  test('rejects stale class IDs and invalid page windows', () {
    final bytes = makeManyMethodsDex();
    final klass = DexInspector.inspectBytes(bytes).classes.single;
    expect(() => DexMethodPager.loadBytes(bytes, klass, start: -1),
        throwsFormatException);
    expect(() => DexMethodPager.loadBytes(bytes, klass, limit: 201),
        throwsFormatException);
    expect(() => DexMethodPager.loadBytes(bytes, klass, start: 206),
        throwsFormatException);
    final stale = Uint8List.fromList(bytes);
    ByteData.sublistView(stale).setUint32(2900, 2, Endian.little);
    expect(() => DexMethodPager.loadBytes(stale, klass),
        throwsFormatException);
  });
}
