import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'arsc_value_reader.dart';
import 'arsc_variant_diff_inspector.dart';
import 'arsc_variant_inspector.dart';
import 'arsc_variant_reference_inspector.dart';

@immutable
class ArscExportRow {
  const ArscExportRow({
    required this.qualifier,
    required this.kind,
    required this.field,
    required this.before,
    required this.after,
    required this.status,
    required this.partial,
  });

  final String qualifier;
  final String kind;
  final String field;
  final String? before;
  final String? after;
  final String status;
  final bool partial;

  Map<String, Object?> toMap() => {
        'qualifier': qualifier,
        'kind': kind,
        'field': field,
        'before': before,
        'after': after,
        'status': status,
        'partial': partial,
      };
}

/// A bounded, portable snapshot of already-decoded configuration comparisons.
/// It never exports the APK, private user files, or resolves Android resources
/// through the device runtime.
@immutable
class ArscVariantExport {
  const ArscVariantExport({
    required this.resourceId,
    required this.resourceName,
    required this.baselineQualifier,
    required this.variants,
    required this.rows,
    required this.truncated,
    required this.warnings,
  });

  final String resourceId;
  final String resourceName;
  final String baselineQualifier;
  final List<Map<String, Object?>> variants;
  final List<ArscExportRow> rows;
  final bool truncated;
  final List<String> warnings;

  String get fileStem => 'droidre-resource-$resourceId';

  String toJson() => const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'resourceId': resourceId,
        'resourceName': resourceName,
        'baselineQualifier': baselineQualifier,
        'note': 'Decoded preview only; no runtime resource selection',
        'truncated': truncated,
        'warnings': warnings,
        'variants': variants,
        'differences': [for (final row in rows) row.toMap()],
      });

  String toCsv() {
    String cell(Object? value) {
      final text = value?.toString() ?? '';
      // Prevent spreadsheet formula execution from untrusted APK strings.
      final suspicious = RegExp(r'^\s*[=+\-@]').hasMatch(text);
      final safeText = suspicious ? "'$text" : text;
      return '"${safeText.replaceAll('"', '""')}"';
    }
    final records = <List<Object?>>[
      [
        'resource_id', 'resource_name', 'baseline_qualifier',
        'variant_qualifier', 'kind', 'field', 'before', 'after',
        'status', 'partial', 'export_truncated',
      ],
      for (final row in rows)
        [
          resourceId, resourceName, baselineQualifier,
          row.qualifier, row.kind, row.field, row.before, row.after,
          row.status, row.partial, truncated,
        ],
    ];
    // BOM helps common spreadsheet programs detect UTF-8 resource names.
    return '\uFEFF${records.map((r) => r.map(cell).join(',')).join('\r\n')}\r\n';
  }
}

class ArscVariantReportExporter {
  const ArscVariantReportExporter._();

  static const maxRows = 1500;

  static ArscVariantExport build(
    ArscVariantComparison comparison,
    Iterable<ArscValue> decodedValues, {
    int rowLimit = maxRows,
  }) {
    if (rowLimit < 1 || rowLimit > maxRows) {
      throw const FormatException('Invalid configuration export row limit');
    }
    final baseline = ArscVariantDiffInspector.baseline(comparison);
    final refs = ArscVariantReferenceInspector(decodedValues);
    final rows = <ArscExportRow>[];
    final warnings = <String>[];
    var truncated = false;

    void add(ArscExportRow row) {
      if (rows.length >= rowLimit) {
        truncated = true;
      } else {
        rows.add(row);
      }
    }

    final variantInfo = <Map<String, Object?>>[];
    for (final candidate in comparison.variants) {
      final qualifier = candidate.configuration?.qualifiers ??
          'unknown config chunk ${candidate.config}';
      variantInfo.add({
        'configChunk': candidate.config,
        'qualifier': qualifier,
        'value': candidate.value,
        'dataType': candidate.dataType,
        'rawData': candidate.rawData,
        'complexBag': candidate.bag != null,
        'bagTruncated': candidate.bag?.truncated ?? false,
      });
      final detail = ArscVariantDiffInspector.compare(baseline, candidate);
      if (detail.partial) {
        warnings.add('Partial bag comparison in $qualifier');
      }
      for (final field in detail.fields) {
        add(ArscExportRow(
          qualifier: qualifier,
          kind: 'raw',
          field: field.field,
          before: field.before,
          after: field.after,
          status: field.change.name,
          partial: detail.partial,
        ));
      }
      for (final ref in refs.compare(baseline, candidate)) {
        add(ArscExportRow(
          qualifier: qualifier,
          kind: 'reference',
          field: ref.field,
          before: ref.before,
          after: ref.after,
          status: ref.change.name,
          partial: ref.change == ArscVariantChange.uncertain,
        ));
      }
    }

    if (comparison.duplicateQualifiers) {
      warnings.add('Duplicate decoded qualifier labels; no runtime '
          'configuration was selected');
    }
    if (truncated) {
      warnings.add('Difference rows limited to $rowLimit; export is partial');
    }
    return ArscVariantExport(
      resourceId: comparison.resourceId.toRadixString(16).padLeft(8, '0'),
      resourceName: comparison.resourceName,
      baselineQualifier: baseline.configuration?.qualifiers ??
          'unknown config chunk ${baseline.config}',
      variants: List.unmodifiable(variantInfo),
      rows: List.unmodifiable(rows),
      truncated: truncated,
      warnings: List.unmodifiable(warnings),
    );
  }
}
