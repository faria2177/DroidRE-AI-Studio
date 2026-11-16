import 'arsc_value_reader.dart';
import 'arsc_variant_diff_inspector.dart';
import 'arsc_variant_inspector.dart';
import 'arsc_variant_reference_inspector.dart';

enum ArscResourceFilter {
  all,
  variants,
  changed,
  night,
  day,
  localized,
  density,
  referenceDifferences,
}

/// Filtering is based on already-decoded resources, not Android's runtime
/// resource matching or device-specific preference ordering.
class ArscResourceVariantFilter {
  ArscResourceVariantFilter(Iterable<ArscValue> values)
      : _variants = ArscVariantInspector(values),
        _references = ArscVariantReferenceInspector(values);

  final ArscVariantInspector _variants;
  final ArscVariantReferenceInspector _references;

  bool matches(ArscValue entry, ArscResourceFilter filter) {
    final comparison = _variants.comparisonFor(entry);
    switch (filter) {
      case ArscResourceFilter.all:
        return true;
      case ArscResourceFilter.variants:
        return comparison != null;
      case ArscResourceFilter.changed:
        return comparison?.valuesDiffer ?? false;
      case ArscResourceFilter.night:
        return entry.configuration?.nightMode == true;
      case ArscResourceFilter.day:
        return entry.configuration?.nightMode == false;
      case ArscResourceFilter.localized:
        return entry.configuration?.locale != null;
      case ArscResourceFilter.density:
        return entry.configuration?.density != null;
      case ArscResourceFilter.referenceDifferences:
        if (comparison == null) {
          return false;
        }
        final base = ArscVariantDiffInspector.baseline(comparison);
        return comparison.variants.any((candidate) =>
            _references.compare(base, candidate).any(
                (diff) => diff.change != ArscVariantChange.same));
    }
  }
}
