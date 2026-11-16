import 'package:flutter/foundation.dart';

import 'arsc_value_reader.dart';

enum ArscStyleStatus {
  complete,
  missing,
  ambiguous,
  cycle,
  nonStyleParent,
  depthLimit,
}

@immutable
class ArscStyleTrace {
  const ArscStyleTrace({
    required this.steps,
    required this.status,
    required this.description,
    required this.hops,
  });

  /// Ordered child-first. Includes the original style.
  final List<ArscValue> steps;
  final ArscStyleStatus status;
  final String description;
  final int hops;

  bool get complete => status == ArscStyleStatus.complete;
}

/// Bounded, preview-only parent tracing for compiled @style resource bags.
///
/// Android style resource variants and external framework resources may be
/// absent from the first decoded entries. Do not select a configuration,
/// infer framework attribute names or claim missing resources are absent
/// from the underlying APK.
class ArscStyleResolver {
  ArscStyleResolver(Iterable<ArscValue> values) {
    for (final entry in values) {
      _byId.putIfAbsent(entry.id, () => <ArscValue>[]).add(entry);
    }
  }

  static const maxDepth = 8;

  final Map<int, List<ArscValue>> _byId = {};

  static String hex(int id) =>
      '0x${id.toRadixString(16).padLeft(8, '0')}';

  /// Returns a symbolic attribute only if one distinct @attr name is decoded
  /// for this exact resource ID. Unavailable/ambiguous IDs stay numeric.
  String attributeLabel(int id) {
    final choices = _byId[id] ?? const <ArscValue>[];
    if (choices.isEmpty) return hex(id);
    final names = choices.map((item) => item.name).toSet();
    if (names.length != 1) {
      return '${hex(id)} (ambiguous attribute name)';
    }
    final name = names.single;
    if (!name.startsWith('@attr/')) return hex(id);
    return '$name (${hex(id)})';
  }

  /// Returns null for simple entries and non-style bags, whose raw parent
  /// fields do not necessarily describe a style inheritance relationship.
  ArscStyleTrace? trace(ArscValue entry, {int depthLimit = maxDepth}) {
    if (entry.bag == null || !entry.name.startsWith('@style/')) return null;
    if (depthLimit < 1 || depthLimit > maxDepth) {
      throw const FormatException('Style chain depth must be between 1 and 8');
    }
    final steps = <ArscValue>[entry];
    final visited = <int>{entry.id};
    var current = entry;

    ArscStyleTrace result(ArscStyleStatus status, String note, int hops) =>
        ArscStyleTrace(
          steps: List<ArscValue>.unmodifiable(steps),
          status: status,
          description: [
            for (final style in steps) '${style.name} (${hex(style.id)})',
          ].join(' → ') + (note.isEmpty ? '' : ' → $note'),
          hops: hops,
        );

    for (var hop = 1; hop <= depthLimit; hop++) {
      final parentId = current.bag!.parentId;
      if (parentId == 0) {
        return result(ArscStyleStatus.complete, 'no further parent', hop - 1);
      }
      if (visited.contains(parentId)) {
        return result(ArscStyleStatus.cycle,
            '${hex(parentId)} (circular style parent)', hop);
      }
      final candidates = _byId[parentId] ?? const <ArscValue>[];
      if (candidates.isEmpty) {
        return result(ArscStyleStatus.missing,
            '${hex(parentId)} (not in decoded preview; may exist in '
            'another package or beyond preview limits)', hop);
      }
      if (candidates.length != 1) {
        return result(ArscStyleStatus.ambiguous,
            '${hex(parentId)} (${candidates.length} configuration variants; '
            'no configuration selected)', hop);
      }
      final parent = candidates.single;
      if (parent.bag == null || !parent.name.startsWith('@style/')) {
        return result(ArscStyleStatus.nonStyleParent,
            '${hex(parentId)} (target is not a decoded style bag)', hop);
      }
      visited.add(parentId);
      steps.add(parent);
      current = parent;
    }
    // A trace with exactly depthLimit edges is complete if the last
    // decoded style has no parent; otherwise it remains explicitly partial.
    if (current.bag!.parentId == 0) {
      return result(ArscStyleStatus.complete, 'no further parent', depthLimit);
    }
    return result(ArscStyleStatus.depthLimit,
        'parent ${hex(current.bag!.parentId)} beyond '
        'depth limit; not verified', depthLimit);
  }
}
