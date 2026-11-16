import 'dart:convert';

import 'package:droidre_ai_studio/services/arsc_configuration.dart';
import 'package:droidre_ai_studio/services/arsc_resource_variant_filter.dart';
import 'package:droidre_ai_studio/services/arsc_value_reader.dart';
import 'package:droidre_ai_studio/services/arsc_variant_inspector.dart';
import 'package:droidre_ai_studio/services/arsc_variant_report_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const defaultConfig = ArscConfiguration(
    chunkIndex: 1, qualifiers: 'default', isDefault: true,
    hasAdditionalQualifiers: false,
  );
  const nightConfig = ArscConfiguration(
    chunkIndex: 2, qualifiers: 'en-rUS-night-xhdpi',
    isDefault: false, hasAdditionalQualifiers: false,
    locale: 'en-rUS', nightMode: true, density: 320,
  );
  const dayConfig = ArscConfiguration(
    chunkIndex: 3, qualifiers: 'notnight',
    isDefault: false, hasAdditionalQualifiers: false,
    nightMode: false,
  );

  test('filters decoded variants, changes, locale/night/density and refs', () {
    const a = ArscValue(0x7f010001, '@string/title', '@0x00000010', 1,
        dataType: 1, rawData: 16, configuration: defaultConfig);
    const b = ArscValue(0x7f010001, '@string/title', '@0x00000020', 2,
        dataType: 1, rawData: 32, configuration: nightConfig);
    const day = ArscValue(0x7f020001, '@string/day', 'Day', 3,
        dataType: 3, rawData: 0, configuration: dayConfig);
    final filter = ArscResourceVariantFilter([a, b, day]);
    expect(filter.matches(day, ArscResourceFilter.all), isTrue);
    expect(filter.matches(day, ArscResourceFilter.variants), isFalse);
    for (final value in [a, b]) {
      expect(filter.matches(value, ArscResourceFilter.variants), isTrue);
      expect(filter.matches(value, ArscResourceFilter.changed), isTrue);
      expect(filter.matches(value, ArscResourceFilter.referenceDifferences),
          isTrue);
    }
    expect(filter.matches(b, ArscResourceFilter.night), isTrue);
    expect(filter.matches(a, ArscResourceFilter.night), isFalse);
    expect(filter.matches(day, ArscResourceFilter.day), isTrue);
    expect(filter.matches(b, ArscResourceFilter.localized), isTrue);
    expect(filter.matches(b, ArscResourceFilter.density), isTrue);
    expect(filter.matches(day, ArscResourceFilter.referenceDifferences),
        isFalse);
  });

  test('export includes raw and reference differences with grounded IDs', () {
    const a = ArscValue(0x7f010001, '@string/title', '@0x00000010', 1,
        dataType: 1, rawData: 16, configuration: defaultConfig);
    const b = ArscValue(0x7f010001, '@string/title', '@0x00000020', 2,
        dataType: 1, rawData: 32, configuration: nightConfig);
    const target = ArscValue(16, '@string/hello', 'Hi', 1);
    final all = [a, b, target];
    final comparison = ArscVariantInspector(all).comparisonFor(a)!;
    final document = ArscVariantReportExporter.build(comparison, all);
    expect(document.resourceId, '7f010001');
    expect(document.fileStem, 'droidre-resource-7f010001');
    expect(document.baselineQualifier, 'default');
    expect(document.rows.where((row) => row.kind == 'reference'), isNotEmpty);
    expect(document.rows.any((row) => row.status == 'changed'), isTrue);
    expect(document.rows.any((row) =>
        row.before?.contains('@string/hello') ?? false), isTrue);
    final json = jsonDecode(document.toJson()) as Map<String, dynamic>;
    expect(json['schemaVersion'], 1);
    expect(json['truncated'], isFalse);
    expect(json['variants'], hasLength(2));
    expect(json['differences'], isNotEmpty);
    expect(json['note'], contains('no runtime'));
    expect(document.toCsv(), startsWith('\uFEFF'));
    expect(document.toCsv(), contains('"reference"'));
  });

  test('CSV escapes commas, quotes/newlines, and spreadsheet formulas', () {
    final document = ArscVariantExport(
      resourceId: '0000000a',
      resourceName: '@string/,name',
      baselineQualifier: 'default',
      variants: const [],
      rows: const [
        ArscExportRow(
          qualifier: 'night',
          kind: 'raw',
          field: 'Resource value',
          before: 'safe',
          after: '=1+1, "hello"\nWorld',
          status: 'changed',
          partial: false,
        ),
      ],
      truncated: false,
      warnings: const [],
    );
    final csv = document.toCsv();
    expect(csv, startsWith('\uFEFF'));
    expect(csv, contains('"@string/,name"'));
    expect(csv, contains('"' + "'=1+1"));
    expect(csv, contains('""hello""'));
    expect(csv, contains('\nWorld'));
  });

  test('limited export marks truncation and refuses invalid row limits', () {
    const a = ArscValue(12, '@string/demo', 'Hi', 1,
        dataType: 3, rawData: 0);
    const b = ArscValue(12, '@string/demo', 'Bye', 2,
        dataType: 3, rawData: 1);
    final comparison = ArscVariantInspector([a, b]).comparisonFor(a)!;
    final output = ArscVariantReportExporter.build(
        comparison, [a, b], rowLimit: 1);
    expect(output.truncated, isTrue);
    expect(output.rows, hasLength(1));
    expect(output.warnings.single, contains('partial'));
    final report = jsonDecode(output.toJson()) as Map<String, dynamic>;
    expect(report['truncated'], isTrue);
    expect(() => ArscVariantReportExporter.build(
        comparison, [a, b], rowLimit: 0), throwsFormatException);
  });
}
