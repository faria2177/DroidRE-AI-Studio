import 'dart:typed_data';

import 'package:droidre_ai_studio/services/dex_method_search.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/many_methods_fixture.dart';

void main() {
  test('finds an unindexed method after the initial 200', () {
    final result = DexMethodSearch.searchBytes(
      makeManyMethodsDex(),
      'METHOD204',
    );
    expect(result.truncated, isFalse);
    expect(result.scannedMethods, 205);
    expect(result.scannedClasses, 1);
    expect(result.methods, hasLength(1));
    expect(result.methods.single.name, 'method204');
    expect(result.methods.single.methodIdIndex, 204);
    expect(result.methods.single.ownerName, 'com.demo.Many');
    expect(result.methods.single.prototype, '()Lcom/demo/Many;');
  });

  test('reports partial results when the result limit is reached', () {
    final result = DexMethodSearch.searchBytes(
      makeManyMethodsDex(),
      'method20',
      resultLimit: 3,
    );
    expect(result.methods, hasLength(3));
    expect(result.methods.first.name, 'method20');
    expect(result.truncated, isTrue);
    expect(result.scannedMethods, lessThan(205));
  });

  test('returns an empty complete result for a missing method', () {
    final result = DexMethodSearch.searchBytes(makeManyMethodsDex(), 'notFound');
    expect(result.methods, isEmpty);
    expect(result.scannedMethods, 205);
    expect(result.truncated, isFalse);
  });

  test('rejects invalid search windows and corrupted class indices', () {
    final bytes = makeManyMethodsDex();
    expect(() => DexMethodSearch.searchBytes(bytes, ''),
        throwsFormatException);
    expect(() => DexMethodSearch.searchBytes(bytes, 'method', resultLimit: 0),
        throwsFormatException);
    expect(() => DexMethodSearch.searchBytes(bytes, 'method', scanLimit: 0),
        throwsFormatException);
    final corrupt = Uint8List.fromList(bytes);
    ByteData.sublistView(corrupt).setUint32(2900, 99, Endian.little);
    expect(() => DexMethodSearch.searchBytes(corrupt, 'method'),
        throwsFormatException);
  });
}
