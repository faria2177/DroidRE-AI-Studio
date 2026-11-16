import 'package:flutter/foundation.dart';

import 'arsc_value_reader.dart';
import 'arsc_variant_diff_inspector.dart';

@immutable
class ArscReferenceDifference {
  const ArscReferenceDifference({
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

/// Compares *raw reference IDs* in decoded resource variants.
///
/// A target name is included only if one unambiguous symbolic name is
/// available in the bounded preview. This is not runtime reference resolution:
/// it cannot select a resource configuration, access external packages or
/// infer the target's effective value.
class ArscVariantReferenceInspector {
  ArscVariantReferenceInspector(Iterable<ArscValue> values) {
    for (final value in values) {
      _byId.putIfAbsent(value.id, () => <ArscValue>[]).add(value);
    }
  }

  final Map<int, List<ArscValue>> _byId = {};

  static bool _isReference(int? kind) =>
      kind == 0x01 || kind == 0x02 || kind == 0x07 || kind == 0x08;

  String _label(int type, int id) {
    final prefix = type == 0x02 || type == 0x08 ? '?' : '@';
    final hex = '0x${id.toRadixString(16).padLeft(8, '0')}';
    if (type == 0x07 || type == 0x08) {
      return '$prefix$hex (dynamic reference; not remapped)';
    }
    final choices = _byId[id] ?? const <ArscValue>[];
    if (choices.isEmpty) {
      return '$prefix$hex (not in decoded preview)';
    }
    final names = choices.map((item) => item.name).toSet();
    if (names.length != 1) {
      return '$prefix$hex (ambiguous decoded names)';
    }
    final name = names.single;
    return '$prefix$hex → $name (preview only)';
  }

  List<ArscReferenceDifference> compare(ArscValue a, ArscValue b) {
    if (a.id != b.id) {
      throw const FormatException('Cannot compare unrelated resource IDs');
    }
    final output = <ArscReferenceDifference>[];

    void record(String field, String? before, String? after,
        {bool uncertain = false}) {
      if (before == null && after == null) {
        return;
      }
      final change = uncertain
          ? ArscVariantChange.uncertain
          : before == after
              ? ArscVariantChange.same
              : before == null
                  ? ArscVariantChange.added
                  : after == null
                      ? ArscVariantChange.removed
                      : ArscVariantChange.changed;
      output.add(ArscReferenceDifference(
          field: field, before: before, after: after, change: change));
    }

    String? scalarReference(ArscValue value) {
      if (!_isReference(value.dataType) || value.rawData == null) {
        return null;
      }
      return _label(value.dataType!, value.rawData!);
    }

    final left = a.bag;
    final right = b.bag;
    if (left == null && right == null) {
      record('Resource reference', scalarReference(a),
          scalarReference(b));
    } else {
      final leftMap = <int, ArscBagItem>{};
      final rightMap = <int, ArscBagItem>{};
      final duplicate = <int>{};

      void collect(ArscBag? bag, Map<int, ArscBagItem> result) {
        if (bag == null) {
          return;
        }
        for (final item in bag.items) {
          if (result.containsKey(item.nameId)) {
            duplicate.add(item.nameId);
          }
          result[item.nameId] = item;
        }
      }

      collect(left, leftMap);
      collect(right, rightMap);
      final keys = {...leftMap.keys, ...rightMap.keys}.toList()..sort();
      for (final id in keys) {
        String? ref(ArscBagItem? item) =>
            item != null && _isReference(item.dataType)
                ? _label(item.dataType, item.rawData)
                : null;
        final before = ref(leftMap[id]);
        final after = ref(rightMap[id]);
        record('Map 0x${id.toRadixString(16).padLeft(8, '0')}',
            before, after,
            uncertain: duplicate.contains(id) ||
                (before == null && (left?.truncated ?? false)) ||
                (after == null && (right?.truncated ?? false)));
      }
      // A switch from a scalar reference to a bag (or vice versa) is
      // represented separately and never silently dropped.
      if (left == null || right == null) {
        record('Resource reference', left == null
            ? scalarReference(a) : null, right == null
            ? scalarReference(b) : null);
      }
    }
    return List<ArscReferenceDifference>.unmodifiable(output);
  }
}
