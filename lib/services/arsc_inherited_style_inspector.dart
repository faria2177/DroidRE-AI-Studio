import 'package:flutter/foundation.dart';

import 'arsc_style_resolver.dart';
import 'arsc_value_reader.dart';

enum ArscStyleAttributeKind {
  declared,
  overridden,
  inherited,
  uncertain,
}

@immutable
class ArscStyleAttributeView {
  const ArscStyleAttributeView({
    required this.attributeId,
    required this.label,
    required this.value,
    required this.dataType,
    required this.rawData,
    required this.sourceName,
    required this.kind,
    this.shadowedValue,
    this.shadowedSource,
  });

  final int attributeId;
  final String label;
  final String value;
  final int dataType;
  final int rawData;
  final String sourceName;
  final ArscStyleAttributeKind kind;
  final String? shadowedValue;
  final String? shadowedSource;
}

@immutable
class ArscInheritedStyleReport {
  const ArscInheritedStyleReport({
    required this.trace,
    required this.attributes,
    required this.partial,
    required this.warnings,
  });

  final ArscStyleTrace trace;
  final List<ArscStyleAttributeView> attributes;
  final bool partial;
  final List<String> warnings;
}

class _KnownAttribute {
  const _KnownAttribute(this.item, this.style, this.shadowed);

  final ArscBagItem item;
  final ArscValue style;
  final _KnownAttribute? shadowed;
}

/// Computes a bounded, read-only *preview* of attribute precedence in the
/// already-decoded style parent chain (root to child).
///
/// This never resolves Android runtime configuration, framework resources,
/// overlays, theme attribute expressions or reference values. Raw map entries
/// can be incomplete (32-item bag previews) and missing parents may be outside
/// the 250-entry decoded ARSC window. Unknown precedence is flagged rather
/// than inferred as fully resolved inheritance.
class ArscInheritedStyleInspector {
  const ArscInheritedStyleInspector._();

  static ArscInheritedStyleReport? inspect(
    ArscValue entry,
    ArscStyleResolver resolver, {
    int depthLimit = ArscStyleResolver.maxDepth,
  }) {
    final trace = resolver.trace(entry, depthLimit: depthLimit);
    if (trace == null) return null;

    final current = <int, _KnownAttribute>{};
    final duplicated = <int>{};
    final warnings = <String>[];

    // Parent values are visited first, so a more specific child map wins.
    // Only entries present in the decoded preview take part in precedence.
    for (final style in trace.steps.reversed) {
      final bag = style.bag!;
      final seenInBag = <int>{};
      for (final item in bag.items) {
        final id = item.nameId;
        if (!seenInBag.add(id)) {
          duplicated.add(id);
          current.remove(id);
          continue;
        }
        if (duplicated.contains(id)) {
          continue;
        }
        current[id] = _KnownAttribute(item, style, current[id]);
      }
    }
    if (duplicated.isNotEmpty) {
      warnings.add(
          'Duplicate attribute IDs within a bag were excluded as ambiguous');
    }

    final incompleteBags = trace.steps.any((style) => style.bag!.truncated);
    final partial = trace.status != ArscStyleStatus.complete ||
        incompleteBags || duplicated.isNotEmpty;
    if (trace.status != ArscStyleStatus.complete) {
      warnings.add(
          'Parent chain is ${trace.status.name}; inherited values are '
          'limited to the decoded chain');
    }
    if (incompleteBags) {
      warnings.add(
          'One or more style bags were truncated; unseen attributes '
          'may override shown ancestors');
    }

    final entries = current.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final attributes = <ArscStyleAttributeView>[];
    for (final item in entries) {
      final attr = item.value;
      final fromChild = identical(attr.style, entry);
      final closerSteps = <ArscValue>[];
      if (!fromChild) {
        for (final step in trace.steps) {
          if (identical(step, attr.style)) {
            break;
          }
          closerSteps.add(step);
        }
      }
      final mayBeShadowed =
          closerSteps.any((step) => step.bag!.truncated);
      final kind = fromChild
          ? (attr.shadowed != null
              ? ArscStyleAttributeKind.overridden
              : ArscStyleAttributeKind.declared)
          : (mayBeShadowed
              ? ArscStyleAttributeKind.uncertain
              : ArscStyleAttributeKind.inherited);

      attributes.add(ArscStyleAttributeView(
        attributeId: item.key,
        label: resolver.attributeLabel(item.key),
        value: attr.item.value,
        dataType: attr.item.dataType,
        rawData: attr.item.rawData,
        sourceName: attr.style.name,
        kind: kind,
        shadowedValue: attr.shadowed?.item.value,
        shadowedSource: attr.shadowed?.style.name,
      ));
    }

    return ArscInheritedStyleReport(
      trace: trace,
      attributes: List<ArscStyleAttributeView>.unmodifiable(attributes),
      partial: partial,
      warnings: List<String>.unmodifiable(warnings),
    );
  }
}
