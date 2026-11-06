import 'dart:typed_data';

import 'package:droidre_ai_studio/services/resource_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List resourceTable() {
  final bytes = Uint8List(308);
  final data = ByteData.sublistView(bytes);
  void u16(int offset, int value) => data.setUint16(offset, value, Endian.little);
  void u32(int offset, int value) => data.setUint32(offset, value, Endian.little);
  u16(0, 0x0002); // RES_TABLE_TYPE
  u16(2, 12);
  u32(4, bytes.length);
  u32(8, 1); // packageCount
  u16(12, 0x0001); // top-level string pool
  u16(14, 8);
  u32(16, 8);
  u16(20, 0x0200); // package
  u16(22, 288);
  u32(24, 288);
  u32(28, 0x7f);
  const name = 'com.demo';
  for (var i = 0; i < name.length; i++) {
    u16(32 + i * 2, name.codeUnitAt(i));
  }
  return bytes;
}

void main() {
  test('reads compiled resource package name and table count', () {
    final result = ResourceInspector.inspectTableBytes(resourceTable());
    expect(result.packageCount, 1);
    expect(result.stringPoolChunks, 1);
    expect(result.packages.single, contains('com.demo'));
    expect(result.packages.single, contains('0x7f'));
  });

  test('rejects malformed compiled resource table chunk', () {
    final bytes = resourceTable();
    ByteData.sublistView(bytes).setUint32(24, 0, Endian.little);
    expect(() => ResourceInspector.inspectTableBytes(bytes), throwsFormatException);
  });

  test('provides bounded text and binary previews', () {
    final text = ResourceInspector.previewBytes('assets/config.json',
      Uint8List.fromList('{"hello":true}'.codeUnits));
    expect(text.textContent, contains('hello'));
    final binary = ResourceInspector.previewBytes('res/xml/settings.xml',
      Uint8List.fromList([3, 0, 8, 0, 0]));
    expect(binary.textContent, isNull);
    expect(binary.hexHeader, startsWith('03 00'));
  });
}
