import 'dart:typed_data';

import 'package:droidre_ai_studio/services/arsc_configuration.dart';
import 'package:droidre_ai_studio/services/arsc_value_reader.dart';
import 'package:droidre_ai_studio/services/arsc_variant_diff_inspector.dart';
import 'package:droidre_ai_studio/services/arsc_variant_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

import 'arsc_configuration_test.dart' show variantTable;

void pack3(Uint8List bytes, int offset, String text, int base) {
  final first = text.codeUnitAt(0) - base;
  final second = text.codeUnitAt(1) - base;
  final third = text.codeUnitAt(2) - base;
  bytes[offset] = 0x80 | (third << 2) | (second >> 3);
  bytes[offset + 1] = ((second << 5) | first) & 0xff;
}

void main() {
  test('decodes packed fil language and numeric 419 region', () {
    final bytes = Uint8List(48);
    ByteData.sublistView(bytes).setUint32(0, 48, Endian.little);
    pack3(bytes, 8, 'fil', 97);
    pack3(bytes, 10, '419', 48);
    final config = ArscConfiguration.parse(
        bytes, start: 0, end: 48, chunkIndex: 7);
    expect(config.locale, 'fil-r419');
    expect(config.bcp47Locale, 'fil-419');
    expect(config.hasAdditionalQualifiers, isFalse);
    expect(config.qualifiers, 'fil-r419');
    expect(config.isDefault, isFalse);
  });

  test('decodes locale script and BCP-47 variant without extra warning', () {
    final bytes = Uint8List(48);
    ByteData.sublistView(bytes).setUint32(0, 48, Endian.little);
    pack3(bytes, 8, 'fil', 97);
    pack3(bytes, 10, '419', 48);
    bytes.setRange(36, 40, 'Latn'.codeUnits);
    bytes.setRange(40, 45, 'POSIX'.codeUnits);
    final config = ArscConfiguration.parse(
        bytes, start: 0, end: 48, chunkIndex: 2);
    expect(config.locale, 'b+fil+Latn+419+posix');
    expect(config.bcp47Locale, 'fil-Latn-419-posix');
    expect(config.localeScript, 'Latn');
    expect(config.localeVariant, 'posix');
    expect(config.hasAdditionalQualifiers, isFalse);
  });

  test('keeps original two-letter language/region decoding intact', () {
    final bytes = Uint8List(48);
    ByteData.sublistView(bytes).setUint32(0, 48, Endian.little);
    bytes.setRange(8, 12, 'enUS'.codeUnits);
    final config = ArscConfiguration.parse(
        bytes, start: 0, end: 48, chunkIndex: 1);
    expect(config.locale, 'en-rUS');
    expect(config.bcp47Locale, 'en-US');
    expect(config.localeScript, isNull);
  });

  test('invalid packed locale and invalid variant remain flagged', () {
    final bytes = Uint8List(48);
    ByteData.sublistView(bytes).setUint32(0, 48, Endian.little);
    // Numeric packed language alphabet is invalid at base a.
    bytes[8] = 0xff;
    bytes[9] = 0xff;
    bytes.setRange(40, 45, [80, 79, 0, 73, 88]);
    final config = ArscConfiguration.parse(
        bytes, start: 0, end: 48, chunkIndex: 1);
    expect(config.locale, isNull);
    expect(config.hasAdditionalQualifiers, isTrue);
    expect(config.qualifiers, contains('additional qualifiers'));
  });

  test('truncated legacy config does not read newer locale fields', () {
    final bytes = Uint8List(36);
    ByteData.sublistView(bytes).setUint32(0, 36, Endian.little);
    bytes.setRange(8, 10, 'en'.codeUnits);
    final config = ArscConfiguration.parse(
        bytes, start: 0, end: 36, chunkIndex: 1);
    expect(config.locale, 'en');
    expect(config.localeScript, isNull);
    expect(config.localeVariant, isNull);
  });

  test('simple resource raw type and data differences are described', () {
    final values = ArscValueReader.parse(variantTable()).values;
    final group = ArscVariantInspector(values).comparisonFor(values.first)!;
    final baseline = ArscVariantDiffInspector.baseline(group);
    expect(baseline.configuration!.isDefault, isTrue);
    final diff = ArscVariantDiffInspector.compare(baseline, values.last);
    expect(diff.changedFields, 1);
    expect(diff.fields.single.change, ArscVariantChange.changed);
    expect(diff.fields.single.before, contains('display=15'));
    expect(diff.fields.single.after, contains('display=25'));
    expect(diff.partial, isFalse);
  });

  test('identical values compare as unchanged even with different qualifiers', () {
    final values = ArscValueReader.parse(
        variantTable(firstValue: 15, secondValue: 15)).values;
    final diff = ArscVariantDiffInspector.compare(values.first, values.last);
    expect(diff.changedFields, 0);
    expect(diff.fields.single.change, ArscVariantChange.same);
  });

  test('detects complex map changes, additions and removals', () {
    const before = ArscValue(10, '@style/Example', 'Bag', 1,
      bag: ArscBag(1, [
        ArscBagItem(3, 'red', 3, 7),
        ArscBagItem(4, 'true', 0x12, 1),
      ], 2, false),
    );
    const after = ArscValue(10, '@style/Example', 'Bag', 2,
      bag: ArscBag(2, [
        ArscBagItem(3, 'blue', 3, 8),
        ArscBagItem(5, 'false', 0x12, 0),
      ], 2, false),
    );
    final diff = ArscVariantDiffInspector.compare(before, after);
    final items = {for (final field in diff.fields) field.field: field};
    expect(items['Bag parent']!.change, ArscVariantChange.changed);
    expect(items['Map 0x00000003']!.change, ArscVariantChange.changed);
    expect(items['Map 0x00000004']!.change, ArscVariantChange.removed);
    expect(items['Map 0x00000005']!.change, ArscVariantChange.added);
    expect(diff.partial, isFalse);
  });

  test('unknown map items in truncated bag are uncertain, not removed', () {
    const original = ArscValue(10, '@style/Example', 'Bag', 1,
      bag: ArscBag(0, [ArscBagItem(3, 'red', 3, 7)], 1, false),
    );
    const next = ArscValue(10, '@style/Example', 'Bag', 2,
      bag: ArscBag(0, [], 8, true),
    );
    final diff = ArscVariantDiffInspector.compare(original, next);
    expect(diff.partial, isTrue);
    expect(diff.fields.last.change, ArscVariantChange.uncertain);
    expect(diff.warnings.single, contains('truncated'));
  });

  test('does not compare unrelated resource IDs', () {
    const a = ArscValue(1, '@string/a', 'A', 1);
    const b = ArscValue(2, '@string/b', 'B', 2);
    expect(() => ArscVariantDiffInspector.compare(a, b),
        throwsFormatException);
  });
}
