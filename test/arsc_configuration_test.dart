import 'dart:typed_data';

import 'package:droidre_ai_studio/services/arsc_configuration.dart';
import 'package:droidre_ai_studio/services/arsc_value_reader.dart';
import 'package:droidre_ai_studio/services/arsc_variant_inspector.dart';
import 'package:droidre_ai_studio/services/resource_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

import 'arsc_value_reader_test.dart' show resourceTableWithValue;

/// Two ResTable_type chunks with the same entry ID but different
/// ResTable_config structs (default and en-rUS/night).
Uint8List variantTable({
  int firstValue = 15,
  int secondValue = 25,
}) {
  final original = resourceTableWithValue(
    value: 'fixture',
    valueKind: 0x10,
    rawValue: 9,
  );
  final originalTypeStart = original.length - 48;
  final bytes = Uint8List(originalTypeStart + 76 * 2);
  bytes.setRange(0, originalTypeStart, original);
  final d = ByteData.sublistView(bytes);
  void u16(int at, int value) => d.setUint16(at, value, Endian.little);
  void u32(int at, int value) => d.setUint32(at, value, Endian.little);

  final globalSize = d.getUint32(16, Endian.little);
  final packageAt = 12 + globalSize;
  u32(4, bytes.length); // ResTable_header
  u32(packageAt + 4, bytes.length - packageAt);

  void addType(int start, int rawValue, {bool night = false}) {
    u16(start, 0x0201); // RES_TABLE_TYPE_TYPE
    u16(start + 2, 56); // 20-byte type header + 36-byte config
    u32(start + 4, 76);
    bytes[start + 8] = 1; // @string
    u32(start + 12, 1); // one resource ID
    u32(start + 16, 60); // entry data after 4-byte index
    u32(start + 20, 36); // ResTable_config.size
    if (night) {
      bytes[start + 28] = 101; // language 'e'
      bytes[start + 29] = 110; // language 'n'
      bytes[start + 30] = 85; // region 'U'
      bytes[start + 31] = 83; // region 'S'
      bytes[start + 32] = 2; // landscape orientation
      u16(start + 34, 320); // xhdpi
      u16(start + 44, 33); // v33
      bytes[start + 49] = 0x20; // UI_MODE_NIGHT_YES
      u16(start + 50, 600); // sw600dp
    }
    u32(start + 56, 0); // entry offset
    u16(start + 60, 8); // ResTable_entry size
    u32(start + 64, 0); // key name index
    u16(start + 68, 8); // Res_value size
    bytes[start + 71] = 0x10; // integer
    u32(start + 72, rawValue);
  }

  addType(originalTypeStart, firstValue);
  addType(originalTypeStart + 76, secondValue, night: true);
  return bytes;
}

void main() {
  test('decodes default and locale/night/density/screen qualifiers', () {
    final report = ArscValueReader.parse(variantTable());
    expect(report.values, hasLength(2));
    final plain = report.values.first;
    final night = report.values.last;
    expect(plain.id, night.id);
    expect(plain.configuration!.isDefault, isTrue);
    expect(plain.configuration!.qualifiers, 'default');
    expect(plain.configuration!.nightMode, isNull);
    expect(night.configuration!.isDefault, isFalse);
    expect(night.configuration!.locale, 'en-rUS');
    expect(night.configuration!.nightMode, isTrue);
    expect(night.configuration!.density, 320);
    expect(night.configuration!.sdkVersion, 33);
    expect(night.configuration!.smallestWidthDp, 600);
    expect(night.configuration!.orientation, 'land');
    expect(night.configuration!.qualifiers, contains('night'));
    expect(night.configuration!.qualifiers, contains('xhdpi'));
    expect(night.configuration!.hasAdditionalQualifiers, isFalse);
    expect(plain.config, 1);
    expect(night.config, 2);
    expect(ResourceInspector.inspectTableBytes(variantTable()).values.last
        .configuration!.nightMode, isTrue);
  });

  test('groups variants by ID and shows whether raw values differ', () {
    final values = ArscValueReader.parse(variantTable()).values;
    final group = ArscVariantInspector(values).comparisonFor(values.first)!;
    expect(group.variants, hasLength(2));
    expect(group.valuesDiffer, isTrue);
    expect(group.duplicateQualifiers, isFalse);
    expect(group.resourceName, '@string/title');
    expect(group.variants.map((v) => v.value), ['15', '25']);

    final identical = ArscValueReader.parse(
        variantTable(firstValue: 15, secondValue: 15)).values;
    expect(ArscVariantInspector(identical)
        .comparisonFor(identical.first)!.valuesDiffer, isFalse);
    expect(ArscVariantInspector([identical.first])
        .comparisonFor(identical.first), isNull);
  });

  test('reports duplicate qualifiers without selecting a winner', () {
    final values = ArscValueReader.parse(variantTable()).values;
    final duplicate = Uint8List.fromList(variantTable());
    final secondType = duplicate.length - 76;
    duplicate.fillRange(secondType + 24, secondType + 56, 0);
    final entries = ArscValueReader.parse(duplicate).values;
    final report = ArscVariantInspector(entries).comparisonFor(entries.first)!;
    expect(report.duplicateQualifiers, isTrue);
    expect(report.valuesDiffer, isTrue);
    expect(values.first.configuration!.qualifiers, 'default');
  });

  test('rejects impossible config size and incomplete config headers', () {
    final corruptedSize = Uint8List.fromList(variantTable());
    final firstType = corruptedSize.length - 152;
    ByteData.sublistView(corruptedSize)
        .setUint32(firstType + 20, 1000, Endian.little);
    expect(() => ArscValueReader.parse(corruptedSize),
        throwsFormatException);

    final corruptedHeader = Uint8List.fromList(variantTable());
    ByteData.sublistView(corruptedHeader)
        .setUint16(firstType + 2, 22, Endian.little);
    expect(() => ArscValueReader.parse(corruptedHeader),
        throwsFormatException);
  });

  test('unknown nonzero configuration bytes are not named default', () {
    final bytes = Uint8List.fromList(variantTable());
    final firstType = bytes.length - 152;
    bytes[firstType + 20 + 16] = 2; // keyboard qualifier (not decoded)
    final result = ArscValueReader.parse(bytes);
    final config = result.values.first.configuration!;
    expect(config.isDefault, isFalse);
    expect(config.hasAdditionalQualifiers, isTrue);
    expect(config.qualifiers, contains('additional qualifiers'));
  });

  test('configuration parser rejects invalid bounds', () {
    expect(() => ArscConfiguration.parse(
      Uint8List(4), start: -1, end: 4, chunkIndex: 1,
    ), throwsFormatException);
  });
}
