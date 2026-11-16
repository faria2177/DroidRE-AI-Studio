import 'package:droidre_ai_studio/services/arsc_style_resolver.dart';
import 'package:droidre_ai_studio/services/arsc_value_reader.dart';
import 'package:flutter_test/flutter_test.dart';

ArscValue style(int id, int parent, {
  String? name,
  int config = 1,
  List<ArscBagItem> items = const [],
}) => ArscValue(
  id, name ?? '@style/style_$id', 'Style bag', config,
  bag: ArscBag(parent, items, items.length, false),
);

void main() {
  test('traces a three-style chain through its decoded parents', () {
    final child = style(0x7f020003, 0x7f020002, name: '@style/Child');
    final middle = style(0x7f020002, 0x7f020001, name: '@style/Middle');
    final root = style(0x7f020001, 0, name: '@style/Root');
    final resolver = ArscStyleResolver([root, child, middle]);
    final trace = resolver.trace(child)!;
    expect(trace.status, ArscStyleStatus.complete);
    expect(trace.hops, 2);
    expect(trace.steps.map((entry) => entry.name),
        ['@style/Child', '@style/Middle', '@style/Root']);
    expect(trace.description, contains('no further parent'));
  });

  test('reports missing parent as preview-only, never absent from APK', () {
    final child = style(0x7f020001, 0x01030004);
    final trace = ArscStyleResolver([child]).trace(child)!;
    expect(trace.status, ArscStyleStatus.missing);
    expect(trace.description, contains('0x01030004'));
    expect(trace.description, contains('not in decoded preview'));
  });

  test('detects parent cycles without repeated traversal', () {
    final a = style(0x7f020001, 0x7f020002);
    final b = style(0x7f020002, 0x7f020001);
    final result = ArscStyleResolver([a, b]).trace(a)!;
    expect(result.status, ArscStyleStatus.cycle);
    expect(result.hops, 2);
    expect(result.steps.length, 2);
  });

  test('does not guess which parent configuration is active', () {
    final child = style(0x7f020002, 0x7f020001);
    final parent1 = style(0x7f020001, 0, config: 1);
    final parent2 = style(0x7f020001, 0, config: 2);
    final trace = ArscStyleResolver([child, parent1, parent2]).trace(child)!;
    expect(trace.status, ArscStyleStatus.ambiguous);
    expect(trace.description, contains('configuration variants'));
    expect(trace.steps.length, 1);
  });

  test('limits parent traversal without falsely claiming completion', () {
    final styles = [
      for (var i = 1; i <= 10; i++)
        style(0x7f020000 + i, i < 10 ? 0x7f020000 + i + 1 : 0),
    ];
    final resolver = ArscStyleResolver(styles);
    final trace = resolver.trace(styles.first, depthLimit: 2)!;
    expect(trace.status, ArscStyleStatus.depthLimit);
    expect(trace.hops, 2);
    expect(trace.steps.length, 3);
    expect(trace.description, contains('not verified'));
    expect(() => resolver.trace(styles.first, depthLimit: 0),
        throwsFormatException);
  });

  test('stops when parent ID points to a simple non-style resource', () {
    final child = style(0x7f020001, 0x7f010001);
    final badParent = ArscValue(
      0x7f010001, '@string/label', 'text', 1);
    final trace = ArscStyleResolver([child, badParent]).trace(child)!;
    expect(trace.status, ArscStyleStatus.nonStyleParent);
    expect(trace.description, contains('not a decoded style bag'));
  });

  test('maps only grounded attr names and keeps numeric fallbacks', () {
    const appAttr = ArscValue(0x7f01000a, '@attr/primaryColor', 'value', 1);
    const otherType = ArscValue(0x7f030001, '@string/title', 'Hi', 1);
    final resolver = ArscStyleResolver([appAttr, otherType]);
    expect(resolver.attributeLabel(0x7f01000a),
        '@attr/primaryColor (0x7f01000a)');
    expect(resolver.attributeLabel(0x01010000), '0x01010000');
    expect(resolver.attributeLabel(0x7f030001), '0x7f030001');
  });

  test('does not fabricate names for ambiguous attribute IDs', () {
    const a = ArscValue(0x7f010001, '@attr/one', '', 1);
    const b = ArscValue(0x7f010001, '@attr/two', '', 2);
    final resolver = ArscStyleResolver([a, b]);
    expect(resolver.attributeLabel(0x7f010001),
        contains('ambiguous attribute name'));
  });

  test('skips non-style bags and simple values', () {
    final arrayBag = ArscValue(
      0x7f030001, '@array/items', 'bag', 1,
      bag: const ArscBag(0, [], 0, false),
    );
    const simple = ArscValue(0x7f010001, '@attr/label', 'value', 1);
    final resolver = ArscStyleResolver([arrayBag, simple]);
    expect(resolver.trace(arrayBag), isNull);
    expect(resolver.trace(simple), isNull);
  });
}
