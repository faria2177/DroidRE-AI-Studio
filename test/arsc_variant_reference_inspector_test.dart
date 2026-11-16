import 'package:droidre_ai_studio/services/arsc_value_reader.dart';
import 'package:droidre_ai_studio/services/arsc_variant_diff_inspector.dart';
import 'package:droidre_ai_studio/services/arsc_variant_reference_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shows concrete ID transitions and preview-only symbolic names', () {
    const before = ArscValue(0x7f020001, '@string/title',
        '@0x7f010001', 1, dataType: 0x01, rawData: 0x7f010001);
    const after = ArscValue(0x7f020001, '@string/title',
        '@0x7f010002', 2, dataType: 0x01, rawData: 0x7f010002);
    const target1 = ArscValue(
        0x7f010001, '@string/first', 'First', 1);
    const target2 = ArscValue(
        0x7f010002, '@string/second', 'Second', 1);
    final diff = ArscVariantReferenceInspector([
      before, after, target1, target2,
    ]).compare(before, after);
    expect(diff, hasLength(1));
    expect(diff.single.change, ArscVariantChange.changed);
    expect(diff.single.before, contains('@string/first'));
    expect(diff.single.after, contains('@string/second'));
    expect(diff.single.after, contains('preview only'));
  });

  test('unresolved targets stay numeric and are not called missing in APK', () {
    const before = ArscValue(0x7f020002, '@style/one',
        '?0x01010000', 1, dataType: 0x02, rawData: 0x01010000);
    const after = ArscValue(0x7f020002, '@style/one',
        '?0x01010001', 2, dataType: 0x02, rawData: 0x01010001);
    final result = ArscVariantReferenceInspector([before, after])
        .compare(before, after);
    expect(result.single.before, contains('?0x01010000'));
    expect(result.single.before, contains('not in decoded preview'));
    expect(result.single.after, contains('?0x01010001'));
  });

  test('repeated resource ID with different names is ambiguous', () {
    const a = ArscValue(1, '@string/title', '@0x00000002', 1,
        dataType: 0x01, rawData: 2);
    const b = ArscValue(1, '@string/title', '@0x00000002', 2,
        dataType: 0x01, rawData: 2);
    const x = ArscValue(2, '@string/a', 'a', 1);
    const y = ArscValue(2, '@string/b', 'b', 2);
    final result = ArscVariantReferenceInspector([a, b, x, y])
        .compare(a, b);
    expect(result.single.change, ArscVariantChange.same);
    expect(result.single.before, contains('ambiguous decoded names'));
  });

  test('dynamic reference remains unremapped even with matching local ID', () {
    const a = ArscValue(1, '@string/title', 'dyn', 1,
        dataType: 0x07, rawData: 2);
    const b = ArscValue(1, '@string/title', 'dyn', 2,
        dataType: 0x07, rawData: 3);
    const local = ArscValue(2, '@string/local', 'not dynamic', 1);
    final diff = ArscVariantReferenceInspector([a, b, local])
        .compare(a, b);
    expect(diff.single.before, contains('dynamic reference; not remapped'));
    expect(diff.single.before, isNot(contains('@string/local')));
  });

  test('detects bag reference differences and unsafe missing map items', () {
    const a = ArscValue(5, '@style/a', 'bag', 1,
        bag: ArscBag(0, [
          ArscBagItem(10, '@0x00000001', 0x01, 1),
          ArscBagItem(11, '?0x00000003', 0x02, 3),
        ], 2, false));
    const b = ArscValue(5, '@style/a', 'bag', 2,
        bag: ArscBag(0, [
          ArscBagItem(10, '@0x00000002', 0x01, 2),
          ArscBagItem(12, '@0x00000004', 0x01, 4),
        ], 3, true));
    final diff = ArscVariantReferenceInspector([a, b])
        .compare(a, b);
    final byField = {for (final item in diff) item.field: item};
    expect(byField['Map 0x0000000a']!.change, ArscVariantChange.changed);
    expect(byField['Map 0x0000000b']!.change, ArscVariantChange.uncertain);
    expect(byField['Map 0x0000000c']!.change, ArscVariantChange.added);
  });

  test('reference added, removed and unrelated IDs', () {
    const ref = ArscValue(3, '@string/a', '@0x00000009', 1,
        dataType: 1, rawData: 9);
    const scalar = ArscValue(3, '@string/a', 'No ref', 2,
        dataType: 3, rawData: 0);
    final inspector = ArscVariantReferenceInspector([ref, scalar]);
    expect(inspector.compare(ref, scalar).single.change,
        ArscVariantChange.removed);
    expect(inspector.compare(scalar, ref).single.change,
        ArscVariantChange.added);
    const different = ArscValue(4, '@string/b', 'B', 1);
    expect(() => inspector.compare(ref, different),
        throwsFormatException);
  });
}
