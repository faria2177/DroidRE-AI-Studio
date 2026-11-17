import 'dart:typed_data';
import 'package:droidre_ai_studio/services/framework_version_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trusted hash comparison is exact and case insensitive', () {
    const hash = '0123456789abcdef0123456789abcdef';
    expect(FrameworkVersionMapping.compareSnapshotHash(hash, hash.toUpperCase()), 'match');
    expect(() => FrameworkVersionMapping.compareSnapshotHash(hash, 'bad'), throwsFormatException);
  });
  test('literal table maps bounded indexes and rejects out of range data', () {
    final bytes = Uint8List(64);
    final d = ByteData.sublistView(bytes);
    d.setUint32(0, 3, Endian.little);
    d.setInt32(4, 1, Endian.little);
    d.setUint32(8, 2, Endian.little);
    d.setInt32(12, 20, Endian.little);
    bytes.setRange(33, 36, 'abc'.codeUnits);
    final report = FrameworkVersionMapping.literals(bytes, 0, 16, 32, 10);
    final rows = report['rows'] as List;
    expect(rows.first['utf8Preview'], 'abc');
    expect(rows.last['status'], 'invalid-range');
    expect(() => FrameworkVersionMapping.literals(bytes, 0, 15, 32, 10), throwsFormatException);
  });
}
