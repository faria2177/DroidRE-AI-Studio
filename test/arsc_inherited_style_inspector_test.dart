import 'package:droidre_ai_studio/services/arsc_inherited_style_inspector.dart';
import 'package:droidre_ai_studio/services/arsc_style_resolver.dart';
import 'package:droidre_ai_studio/services/arsc_value_reader.dart';
import 'package:flutter_test/flutter_test.dart';

ArscBagItem field(int id, String value, {int type = 3, int raw = 0}) =>
    ArscBagItem(id, value, type, raw);

ArscValue style(
  int id,
  int parent,
  List<ArscBagItem> fields, {
  String? name,
  bool truncated = false,
}) =>
    ArscValue(
      id,
      name ?? '@style/style_$id',
      'Style bag',
      1,
      bag: ArscBag(parent, fields, fields.length + (truncated ? 10 : 0),
          truncated),
    );

void main() {
  test('compares child overrides and nearest-parent inherited attributes', () {
    final root = style(0x7f020001, 0, [
      field(1, 'red'),
      field(2, '12'),
    ], name: '@style/Root');
    final middle = style(0x7f020002, root.id, [
      field(1, 'yellow'),
      field(3, 'bold'),
    ], name: '@style/Middle');
    final child = style(0x7f020003, middle.id, [
      field(1, 'blue'),
      field(4, 'true', type: 0x12, raw: 1),
    ], name: '@style/Child');
    const attr = ArscValue(1, '@attr/colorPrimary', 'attr', 1);
    final resolver = ArscStyleResolver([root, middle, child, attr]);
    final report = ArscInheritedStyleInspector.inspect(child, resolver)!;
    expect(report.partial, isFalse);
    expect(report.trace.status, ArscStyleStatus.complete);
    expect(report.attributes, hasLength(4));
    final byId = {for (final item in report.attributes)
      item.attributeId: item};
    expect(byId[1]!.label, '@attr/colorPrimary (0x00000001)');
    expect(byId[1]!.kind, ArscStyleAttributeKind.overridden);
    expect(byId[1]!.value, 'blue');
    expect(byId[1]!.shadowedValue, 'yellow');
    expect(byId[1]!.shadowedSource, '@style/Middle');
    expect(byId[2]!.kind, ArscStyleAttributeKind.inherited);
    expect(byId[2]!.sourceName, '@style/Root');
    expect(byId[3]!.kind, ArscStyleAttributeKind.inherited);
    expect(byId[3]!.sourceName, '@style/Middle');
    expect(byId[4]!.kind, ArscStyleAttributeKind.declared);
    expect(byId[4]!.rawData, 1);
    expect(byId[4]!.dataType, 0x12);
  });

  test('same raw value still shadows an inherited declaration', () {
    final parent = style(11, 0, [field(99, 'same', raw: 4)]);
    final child = style(12, 11, [field(99, 'same', raw: 4)]);
    final report = ArscInheritedStyleInspector.inspect(
      child, ArscStyleResolver([parent, child]))!;
    expect(report.attributes.single.kind, ArscStyleAttributeKind.overridden);
    expect(report.attributes.single.shadowedValue, 'same');
  });

  test('missing ancestor remains explicitly partial', () {
    final child = style(3, 0x01030004, [field(15, 'value')]);
    final report = ArscInheritedStyleInspector.inspect(
      child, ArscStyleResolver([child]))!;
    expect(report.partial, isTrue);
    expect(report.trace.status, ArscStyleStatus.missing);
    expect(report.warnings.join(' '), contains('missing'));
    expect(report.attributes.single.kind, ArscStyleAttributeKind.declared);
  });

  test('truncated child bag makes apparently inherited values uncertain', () {
    final parent = style(10, 0, [field(7, 'parent'), field(8, 'other')]);
    final child = style(20, 10, [field(9, 'child')], truncated: true);
    final report = ArscInheritedStyleInspector.inspect(
      child, ArscStyleResolver([parent, child]))!;
    expect(report.partial, isTrue);
    final byId = {for (final item in report.attributes)
      item.attributeId: item};
    expect(byId[7]!.kind, ArscStyleAttributeKind.uncertain);
    expect(byId[8]!.kind, ArscStyleAttributeKind.uncertain);
    expect(byId[9]!.kind, ArscStyleAttributeKind.declared);
    expect(report.warnings.join(' '), contains('truncated'));
  });

  test('truncated distant ancestor does not hide known closer override', () {
    final root = style(1, 0, [field(33, 'root')], truncated: true);
    final parent = style(2, 1, [field(33, 'parent')]);
    final child = style(3, 2, [field(33, 'child')]);
    final report = ArscInheritedStyleInspector.inspect(
      child, ArscStyleResolver([root, parent, child]))!;
    expect(report.partial, isTrue);
    expect(report.attributes.single.kind, ArscStyleAttributeKind.overridden);
    expect(report.attributes.single.shadowedValue, 'parent');
  });

  test('duplicate map attribute names are excluded rather than guessed', () {
    final bad = style(1, 0,
        [field(2, 'first'), field(2, 'conflict'), field(3, 'safe')]);
    final report = ArscInheritedStyleInspector.inspect(
      bad, ArscStyleResolver([bad]))!;
    expect(report.partial, isTrue);
    expect(report.attributes.map((x) => x.attributeId), [3]);
    expect(report.warnings.join(' '), contains('Duplicate attribute'));
  });

  test('bounded or ambiguous ancestor chains remain partial previews', () {
    final first = style(1, 2, [field(10, 'first')]);
    final second = style(2, 3, [field(20, 'second')]);
    final third = style(3, 0, [field(30, 'third')]);
    final resolver = ArscStyleResolver([first, second, third]);
    final report = ArscInheritedStyleInspector.inspect(
      first, resolver, depthLimit: 1)!;
    expect(report.partial, isTrue);
    expect(report.trace.status, ArscStyleStatus.depthLimit);
    expect(report.attributes.map((x) => x.attributeId),
        [10, 20]);
    final duplicateParent = style(2, 0, [field(40, 'variant')]);
    final ambiguous = ArscInheritedStyleInspector.inspect(
      first, ArscStyleResolver([first, second, duplicateParent]))!;
    expect(ambiguous.trace.status, ArscStyleStatus.ambiguous);
    expect(ambiguous.attributes, hasLength(1));
    expect(ambiguous.partial, isTrue);
  });

  test('does not compare non-style bags or simple values', () {
    final array = ArscValue(
      0x7f030001, '@array/list', 'bag', 1,
      bag: const ArscBag(0, [], 0, false),
    );
    const simple = ArscValue(0x7f010001, '@string/title', 'text', 1);
    final resolver = ArscStyleResolver([array, simple]);
    expect(ArscInheritedStyleInspector.inspect(array, resolver), isNull);
    expect(ArscInheritedStyleInspector.inspect(simple, resolver), isNull);
  });
}
