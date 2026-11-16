import 'package:droidre_ai_studio/services/arsc_reference_resolver.dart';
import 'package:droidre_ai_studio/services/arsc_value_reader.dart';
import 'package:flutter_test/flutter_test.dart';

ArscValue resource(int id, String name, String value, {
  int? reference,
  int config = 1,
}) => ArscValue(
  id,
  name,
  value,
  config,
  dataType: reference == null ? 0x03 : 0x01,
  rawData: reference,
);

void main() {
  test('traces a two-hop reference to a decoded string', () {
    final start = resource(0x7f010000, '@string/title', '@0x7f010001',
        reference: 0x7f010001);
    final middle = resource(0x7f010001, '@string/alias', '@0x7f010002',
        reference: 0x7f010002);
    final end = resource(0x7f010002, '@string/real_title', 'Hello!');
    final resolver = ArscReferenceResolver([start, middle, end]);

    final trace = resolver.trace(start)!;
    expect(trace.status, ArscReferenceStatus.resolved);
    expect(trace.hops, 2);
    expect(trace.description, contains('@string/alias'));
    expect(trace.description, contains('@string/real_title = Hello!'));
    expect(resolver.trace(end), isNull);
  });

  test('reports missing target as unavailable in the decoded preview', () {
    final start = resource(0x7f010000, '@string/start', '@0x7f010099',
        reference: 0x7f010099);
    final trace = ArscReferenceResolver([start]).trace(start)!;
    expect(trace.status, ArscReferenceStatus.missing);
    expect(trace.description, contains('not in decoded preview'));
    expect(trace.description, contains('0x7f010099'));
  });

  test('rejects cycles rather than incorrectly resolving them', () {
    final a = resource(0x7f010000, '@string/a', '@0x7f010001',
        reference: 0x7f010001);
    final b = resource(0x7f010001, '@string/b', '@0x7f010000',
        reference: 0x7f010000);
    final trace = ArscReferenceResolver([a, b]).trace(a)!;
    expect(trace.status, ArscReferenceStatus.cycle);
    expect(trace.description, contains('circular reference'));
  });

  test('refuses to select among configuration variants', () {
    final start = resource(0x7f010000, '@string/a', '@0x7f010001',
        reference: 0x7f010001);
    final us = resource(0x7f010001, '@string/target', 'color',
        config: 2);
    final bn = resource(0x7f010001, '@string/target', 'রং',
        config: 3);
    final trace = ArscReferenceResolver([start, us, bn]).trace(start)!;
    expect(trace.status, ArscReferenceStatus.ambiguous);
    expect(trace.description, contains('configuration variants'));
    expect(trace.description, isNot(contains('= color')));
  });

  test('limits long chains without falsely claiming a final value', () {
    final values = <ArscValue>[
      for (var i = 0; i < 10; i++)
        resource(0x7f010000 + i, '@string/value$i',
            '@0x${(0x7f010001 + i).toRadixString(16)}',
            reference: 0x7f010001 + i),
    ];
    values.add(resource(0x7f01000a, '@string/terminal', 'final'));
    final resolver = ArscReferenceResolver(values);
    final trace = resolver.trace(values.first)!;
    expect(trace.status, ArscReferenceStatus.depthLimit);
    expect(trace.hops, ArscReferenceResolver.maxDepth);
    expect(trace.description, isNot(contains('= final')));
    expect(() => resolver.trace(values.first, depthLimit: 0),
        throwsFormatException);
  });
}
