import 'package:flutter/foundation.dart';

import 'arsc_value_reader.dart';

enum ArscReferenceStatus {
  resolved,
  missing,
  ambiguous,
  cycle,
  depthLimit,
}

@immutable
class ArscReferenceTrace {
  const ArscReferenceTrace({
    required this.status,
    required this.description,
    required this.hops,
  });

  final ArscReferenceStatus status;
  final String description;
  final int hops;

  bool get resolved => status == ArscReferenceStatus.resolved;
}

/// Traces only TYPE_REFERENCE (0x01) edges through the values already
/// decoded from resources.arsc. A preview does not include all resources,
/// so missing targets never imply a missing resource in the original APK.
///
/// Configuration variants are not resolved against device qualifiers. If a
/// target ID has several decoded configurations, refuse to guess a winner.
class ArscReferenceResolver {
  ArscReferenceResolver(Iterable<ArscValue> values) {
    for (final entry in values) {
      _byId.putIfAbsent(entry.id, () => <ArscValue>[]).add(entry);
    }
  }

  static const maxDepth = 8;

  final Map<int, List<ArscValue>> _byId = {};

  ArscReferenceTrace? trace(ArscValue entry, {int depthLimit = maxDepth}) {
    if (entry.dataType != 0x01 || entry.rawData == null) return null;
    if (depthLimit < 1 || depthLimit > maxDepth) {
      throw const FormatException('Reference depth limit must be 1–8');
    }

    String hex(int id) => '0x${id.toRadixString(16).padLeft(8, '0')}';
    final visited = <int>{entry.id};
    final path = <String>[entry.name];
    var current = entry;

    for (var hop = 1; hop <= depthLimit; hop++) {
      final nextId = current.rawData!;
      final candidates = _byId[nextId] ?? const <ArscValue>[];
      if (candidates.isEmpty) {
        return ArscReferenceTrace(
          status: ArscReferenceStatus.missing,
          description: '${path.join(' → ')} → ${hex(nextId)} '
              '(not in decoded preview; may exist elsewhere in the table)',
          hops: hop,
        );
      }
      if (candidates.length > 1) {
        return ArscReferenceTrace(
          status: ArscReferenceStatus.ambiguous,
          description: '${path.join(' → ')} → ${hex(nextId)} '
              '(${candidates.length} configuration variants; '
              'no device configuration selected)',
          hops: hop,
        );
      }

      final next = candidates.single;
      path.add(next.name);
      if (!visited.add(next.id)) {
        return ArscReferenceTrace(
          status: ArscReferenceStatus.cycle,
          description: '${path.join(' → ')} (circular reference)',
          hops: hop,
        );
      }
      if (next.dataType != 0x01 || next.rawData == null) {
        return ArscReferenceTrace(
          status: ArscReferenceStatus.resolved,
          description: '${path.join(' → ')} = ${next.value}',
          hops: hop,
        );
      }
      current = next;
    }
    return ArscReferenceTrace(
      status: ArscReferenceStatus.depthLimit,
      description: '${path.join(' → ')} '
          '(reference depth limit reached; target not verified)',
      hops: depthLimit,
    );
  }
}
