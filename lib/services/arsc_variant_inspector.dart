import 'package:flutter/foundation.dart';

import 'arsc_value_reader.dart';

@immutable
class ArscVariantComparison {
  const ArscVariantComparison({
    required this.resourceId,
    required this.resourceName,
    required this.variants,
    required this.valuesDiffer,
    required this.duplicateQualifiers,
  });

  final int resourceId;
  final String resourceName;
  final List<ArscValue> variants;
  final bool valuesDiffer;
  final bool duplicateQualifiers;
}

/// Groups only entries already present in the bounded ARSC decode preview.
/// This is NOT Android's runtime resource configuration selection algorithm.
class ArscVariantInspector {
  ArscVariantInspector(Iterable<ArscValue> values) {
    for (final value in values) {
      _byId.putIfAbsent(value.id, () => <ArscValue>[]).add(value);
    }
  }

  final Map<int, List<ArscValue>> _byId = {};

  ArscVariantComparison? comparisonFor(ArscValue value) {
    final group = _byId[value.id];
    if (group == null || group.length < 2) return null;
    final ordered = List<ArscValue>.of(group)
      ..sort((a, b) => a.config.compareTo(b.config));
    final fingerprints = ordered.map(_fingerprint).toSet();
    final qualifiers = ordered
        .map((entry) => entry.configuration?.qualifiers ?? 'unknown')
        .toList();
    return ArscVariantComparison(
      resourceId: value.id,
      resourceName: value.name,
      variants: List<ArscValue>.unmodifiable(ordered),
      valuesDiffer: fingerprints.length > 1,
      duplicateQualifiers: qualifiers.toSet().length != qualifiers.length,
    );
  }

  String _fingerprint(ArscValue value) {
    final bag = value.bag;
    if (bag == null) {
      return '${value.dataType}:${value.rawData}:${value.value}';
    }
    return '${bag.parentId}:${bag.totalItems}:${bag.truncated}:'
        '${bag.items.map((item) =>
            '${item.nameId}/${item.dataType}/${item.rawData}/${item.value}')
            .join('|')}';
  }
}
