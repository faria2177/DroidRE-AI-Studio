import 'dart:convert';
import 'dart:typed_data';

import 'package:droidre_ai_studio/services/arsc_value_reader.dart';
import 'package:droidre_ai_studio/services/resource_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List pool(List<String> strings) {
  final data = <int>[];
  final offsets = <int>[];
  for (final item in strings) {
    final encoded = utf8.encode(item);
    offsets.add(data.length);
    data.addAll([item.codeUnits.length, encoded.length, ...encoded, 0]);
  }
  final base = 28 + 4 * strings.length;
  final size = (base + data.length + 3) & ~3;
  final bytes = Uint8List(size);
  final view = ByteData.sublistView(bytes);
  void u16(int at, int value) => view.setUint16(at, value, Endian.little);
  void u32(int at, int value) => view.setUint32(at, value, Endian.little);
  u16(0, 1);
  u16(2, 28);
  u32(4, size);
  u32(8, strings.length);
  u32(16, 0x100); // UTF-8
  u32(20, base);
  for (var i = 0; i < offsets.length; i++) {
    u32(28 + i * 4, offsets[i]);
  }
  bytes.setRange(base, base + data.length, data);
  return bytes;
}

Uint8List resourceTableWithValue({
  String value = 'Hello',
  int typeFlags = 0,
  bool complex = false,
  int valueKind = 3,
  int rawValue = 0,
}) {
  final global = pool([value]);
  final types = pool(['string']);
  final keys = pool(['title']);
  final type = Uint8List(48);
  final t = ByteData.sublistView(type);
  void t16(int at, int value) => t.setUint16(at, value, Endian.little);
  void t32(int at, int value) => t.setUint32(at, value, Endian.little);
  t16(0, 0x0201);
  t16(2, 28);
  t32(4, type.length);
  type[8] = 1; // Type index
  type[9] = typeFlags;
  t32(12, 1); // One entry
  t32(16, 32); // entriesStart
  t32(20, 8); // Configuration bytes
  if (typeFlags == 1) {
    t16(28, 4); // Sparse entry index
    t16(30, 0); // offset in 4-byte units
  } else if (typeFlags == 2) {
    t16(28, 0); // 16-bit offset
  } else {
    t32(28, 0); // 32-bit offset
  }
  t16(32, 8); // ResTable_entry size
  t16(34, complex ? 1 : 0);
  t32(36, 0); // key string index
  t16(40, 8); // Res_value size
  type[43] = valueKind;
  t32(44, rawValue); // raw Res_value (string index or reference)

  final packageSize = 288 + types.length + keys.length + type.length;
  final pkg = Uint8List(packageSize);
  final p = ByteData.sublistView(pkg);
  void p16(int at, int value) => p.setUint16(at, value, Endian.little);
  void p32(int at, int value) => p.setUint32(at, value, Endian.little);
  p16(0, 0x0200);
  p16(2, 288);
  p32(4, pkg.length);
  p32(8, 0x7f);
  const name = 'com.demo';
  for (var i = 0; i < name.length; i++) {
    p16(12 + 2 * i, name.codeUnitAt(i));
  }
  p32(268, 288);
  p32(276, 288 + types.length);
  pkg.setRange(288, 288 + types.length, types);
  pkg.setRange(288 + types.length, 288 + types.length + keys.length, keys);
  pkg.setRange(288 + types.length + keys.length, pkg.length, type);

  final bytes = Uint8List(12 + global.length + pkg.length);
  final header = ByteData.sublistView(bytes);
  header.setUint16(0, 2, Endian.little);
  header.setUint16(2, 12, Endian.little);
  header.setUint32(4, bytes.length, Endian.little);
  header.setUint32(8, 1, Endian.little);
  bytes.setRange(12, 12 + global.length, global);
  bytes.setRange(12 + global.length, bytes.length, pkg);
  return bytes;
}


Uint8List resourceTableWithStyleBag() {
  final source = resourceTableWithValue(value: 'Blue');
  // Expand the final ResTable_type chunk from 48 to 72 bytes to hold a
  // ResTable_map_entry and two ResTable_map records.
  final result = Uint8List(source.length + 24);
  result.setRange(0, source.length, source);
  final d = ByteData.sublistView(result);
  void u16(int at, int value) => d.setUint16(at, value, Endian.little);
  void u32(int at, int value) => d.setUint32(at, value, Endian.little);
  final typeAt = source.length - 48;
  final packageAt = 12 + pool(['Blue']).length;
  u32(4, result.length);
  u32(packageAt + 4, result.length - packageAt);
  u32(typeAt + 4, 72);
  u16(typeAt + 32, 16); // ResTable_map_entry size
  u16(typeAt + 34, 1); // FLAG_COMPLEX
  u32(typeAt + 36, 0); // key string index
  u32(typeAt + 40, 0x7f020001); // parent style reference
  u32(typeAt + 44, 2); // map count

  // Map 0: android:colorAccent -> global string "Blue"
  u32(typeAt + 48, 0x01010000);
  u16(typeAt + 52, 8);
  result[typeAt + 55] = 3;
  u32(typeAt + 56, 0);

  // Map 1: android:textColor -> boolean true
  u32(typeAt + 60, 0x01010001);
  u16(typeAt + 64, 8);
  result[typeAt + 67] = 0x12;
  u32(typeAt + 68, 1);
  return result;
}

void main() {
  test('resolves compiled ID, type/key and pooled UTF-8 value', () {
    final bytes = resourceTableWithValue(value: 'বাংলা');
    final result = ArscValueReader.parse(bytes);
    expect(result.values, hasLength(1));
    expect(result.values.single.idHex, '0x7f010000');
    expect(result.values.single.name, '@string/title');
    expect(result.values.single.value, 'বাংলা');
    expect(result.truncated, isFalse);
    final summary = ResourceInspector.inspectTableBytes(bytes);
    expect(summary.values.single.value, 'বাংলা');
    expect(summary.packages.single, contains('com.demo'));
  });

  test('preserves raw reference ID without claiming it is resolved', () {
    final report = ArscValueReader.parse(resourceTableWithValue(
      valueKind: 1,
      rawValue: 0x7f010012,
    ));
    final item = report.values.single;
    expect(item.id, 0x7f010000);
    expect(item.value, '@0x7f010012');
    expect(item.dataType, 1);
    expect(item.rawData, 0x7f010012);
  });

  test('handles offset16 and sparse entry indexes', () {
    final offset16 = ArscValueReader.parse(
      resourceTableWithValue(typeFlags: 2));
    expect(offset16.values.single.idHex, '0x7f010000');
    final sparse = ArscValueReader.parse(
      resourceTableWithValue(typeFlags: 1));
    expect(sparse.values.single.idHex, '0x7f010004');
  });

  test('skips complex entries without presenting fabricated values', () {
    final result = ArscValueReader.parse(
      resourceTableWithValue(complex: true));
    expect(result.values, isEmpty);
    expect(result.warnings.join(' '), contains('Complex'));
  });

  test('decodes bounded style bag map names and typed values', () {
    final result = ArscValueReader.parse(resourceTableWithStyleBag());
    expect(result.values, hasLength(1));
    final style = result.values.single;
    expect(style.name, '@string/title');
    expect(style.bag, isNotNull);
    expect(style.bag!.parentHex, '0x7f020001');
    expect(style.bag!.totalItems, 2);
    expect(style.bag!.items.map((item) => item.nameHex),
        ['0x01010000', '0x01010001']);
    expect(style.bag!.items.map((item) => item.value),
        ['Blue', 'true']);
    expect(style.bag!.truncated, isFalse);
    expect(result.warnings, isEmpty);
    expect(ResourceInspector.inspectTableBytes(
        resourceTableWithStyleBag()).values.single.bag!.items, hasLength(2));
  });

  test('rejects out-of-bounds style map count', () {
    final input = resourceTableWithStyleBag();
    final typeAt = input.length - 72;
    ByteData.sublistView(input)
        .setUint32(typeAt + 44, 100000, Endian.little);
    expect(() => ArscValueReader.parse(input), throwsFormatException);
  });

  test('reports bounded results and rejects invalid entry offsets', () {
    final input = resourceTableWithValue();
    final limited = ArscValueReader.parse(input, scanLimit: 1);
    expect(limited.values, hasLength(1));
    expect(limited.truncated, isFalse);
    final corrupt = Uint8List.fromList(input);
    final typeOffset = corrupt.length - 48;
    ByteData.sublistView(corrupt).setUint32(
      typeOffset + 28, 0xfffffff0, Endian.little);
    expect(() => ArscValueReader.parse(corrupt), throwsFormatException);
  });
}
