import 'package:flutter/foundation.dart';

import 'arsc_value_reader.dart';
import 'arsc_variant_inspector.dart';

enum ArscVariantChange {
  same,
  changed,
  added,
  removed,
  uncertain,
}

@immutable
class ArscVariantFieldDifference {
  const ArscVariantFieldDifference({
    required this.field,
    required this.before,
    required this.after,
    required this.change,
  });

  final String field;
  final String? before;
  final String? after;
  final ArscVariantChange change;
}

@immutable
class ArscVariantDetail {
  const ArscVariantDetail({
    required this.baseline,
    required this.candidate,
    required this.fields,
    required this.partial,
    required this.warnings,
  });

  final ArscValue baseline;
  final ArscValue candidate;
  final List<ArscVariantFieldDifference> fields;
  final bool partial;
  final List<String> warnings;

  int get changedFields => fields.where((item) =>
      item.change != ArscVariantChange.same).length;
}

/// Static comparison of the raw decoded values in two ARSC configurations.
/// Does not select the device's active resource or resolve references.
class ArscVariantDiffInspector {
  const ArscVariantDiffInspector._();

  static ArscValue baseline(ArscVariantComparison comparison) {
    final defaults = comparison.variants.where(
        (entry) => entry.configuration?.isDefault == true).toList();
    return defaults.length == 1 ? defaults.single : comparison.variants.first;
  }

  static ArscVariantDetail compare(
    ArscValue baseline,
    ArscValue candidate,
  ) {
    if (baseline.id != candidate.id) {
      throw const FormatException('Cannot compare different resource IDs');
    }
    final fields = <ArscVariantFieldDifference>[];
    final warnings = <String>[];

    void add(String key, String? from, String? to,
        {bool uncertain = false}) {
      final change = uncertain ? ArscVariantChange.uncertain :
          from == to ? ArscVariantChange.same :
          from == null ? ArscVariantChange.added :
          to == null ? ArscVariantChange.removed :
          ArscVariantChange.changed;
      fields.add(ArscVariantFieldDifference(
          field: key, before: from, after: to, change: change));
    }

    String scalar(ArscValue value) =>
        'TYPE_0x${(value.dataType ?? 0).toRadixString(16)} '
        'raw=${value.rawData == null ? 'n/a' :
            '0x${value.rawData!.toRadixString(16)}'} '
        'display=${value.value}';

    final a = baseline.bag;
    final b = candidate.bag;
    if (a == null || b == null) {
      add('Resource value', a == null ? scalar(baseline) :
          'complex bag', b == null ? scalar(candidate) : 'complex bag');
      if ((a == null) != (b == null)) {
        warnings.add('Resource changed between simple and complex entry');
      }
    } else {
      add('Bag parent',
          '0x${a.parentId.toRadixString(16)}',
          '0x${b.parentId.toRadixString(16)}');
      final aMap = <int, ArscBagItem>{};
      final bMap = <int, ArscBagItem>{};
      final repeated = <int>{};
      void index(List<ArscBagItem> items, Map<int, ArscBagItem> target) {
        for (final item in items) {
          if (target.containsKey(item.nameId)) {
            repeated.add(item.nameId);
          }
          target[item.nameId] = item;
        }
      }
      index(a.items, aMap);
      index(b.items, bMap);
      if (repeated.isNotEmpty) {
        warnings.add('Duplicate map keys: comparisons marked uncertain');
      }
      final keys = {...aMap.keys, ...bMap.keys}.toList()..sort();
      for (final id in keys) {
        final fromItem = aMap[id];
        final toItem = bMap[id];
        String? display(ArscBagItem? item) => item == null ? null :
            'type 0x${item.dataType.toRadixString(16)}, '
            'raw 0x${item.rawData.toRadixString(16)}: ${item.value}';
        add('Map 0x${id.toRadixString(16).padLeft(8, '0')}',
            display(fromItem), display(toItem),
            uncertain: repeated.contains(id) ||
                (fromItem == null && a.truncated) ||
                (toItem == null && b.truncated));
      }
    }
    final partial = (a?.truncated ?? false) || (b?.truncated ?? false) ||
        warnings.any((note) => note.startsWith('Duplicate'));
    if ((a?.truncated ?? false) || (b?.truncated ?? false)) {
      warnings.add('A bag was truncated to a preview; unseen map items '
          'cannot be compared');
    }
    return ArscVariantDetail(
      baseline: baseline,
      candidate: candidate,
      fields: List.unmodifiable(fields),
      partial: partial,
      warnings: List.unmodifiable(warnings),
    );
  }
}
