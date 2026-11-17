import 'android_binary_xml_decoder.dart';
import 'arsc_reference_resolver.dart';
import 'arsc_value_reader.dart';
import 'resource_inspector.dart';

/// Read-only metadata. Reference names come from decoded table entries,
/// never from guessing an Android platform name or runtime configuration.
class ResourceRecoveryIndex {
  ResourceRecoveryIndex(this.table) {
    for (final item in table?.values ?? const <ArscValue>[]) {
      _byId.putIfAbsent(item.id, () => <ArscValue>[]).add(item);
    }
  }

  final ResourceTableSummary? table;
  final Map<int, List<ArscValue>> _byId = {};

  Map<String, Object?> reference(AndroidXmlReference ref) {
    final variants = _byId[ref.id] ?? const <ArscValue>[];
    final names = variants.map((item) => item.name).toSet().toList()..sort();
    final dynamicReference = ref.type == 7 || ref.type == 8;
    final attribute = ref.type == 2 || ref.type == 8;
    final unique = names.length == 1 &&
        (!attribute || names.single.startsWith('@attr/'));
    return {
      'element': ref.element,
      'attribute': ref.attribute,
      'type': ref.type,
      'id': ref.idHex,
      'rawValuePresent': ref.rawValuePresent,
      'status': dynamicReference ? 'dynamic-unresolved' :
          table == null ? 'table-unavailable' :
          variants.isEmpty ? 'not-in-preview' :
          unique ? 'known-name' : 'ambiguous-or-incompatible-name',
      'nameHint': !dynamicReference && unique ? names.single : null,
      'candidateNames': dynamicReference ? <String>[] : names,
      'decodedVariants': dynamicReference ? 0 : variants.length,
    };
  }

  Map<String, Object?> toJson() {
    final summary = table;
    final resolver = ArscReferenceResolver(summary?.values ?? const <ArscValue>[]);
    return {
      'schemaVersion': 1,
      'available': summary != null,
      'note': 'Bounded compiled resource preview, not a runtime resource resolver.',
      'packageCount': summary?.packageCount,
      'packages': summary?.packages ?? const <String>[],
      'scannedSlots': summary?.scannedSlots,
      'partial': summary == null || summary.valuesTruncated ||
          summary.valueWarnings.isNotEmpty,
      'warnings': summary?.valueWarnings ?? const <String>[],
      'values': [
        for (final item in summary?.values ?? const <ArscValue>[])
          _entry(item, resolver),
      ],
    };
  }

  Map<String, Object?> _entry(ArscValue item, ArscReferenceResolver resolver) {
    final trace = resolver.trace(item);
    final bag = item.bag;
    return {
      'id': item.idHex,
      'name': item.name,
      'value': item.value,
      'configurationIndex': item.config,
      'dataType': item.dataType,
      'rawData': item.rawData,
      if (trace != null) 'referenceTrace': {
        'status': trace.status.name, 'description': trace.description,
        'hops': trace.hops,
      },
      if (bag != null) 'bag': {
        'parentId': bag.parentHex,
        'totalItems': bag.totalItems,
        'truncated': bag.truncated,
        'items': [
          for (final value in bag.items)
            {'nameId': value.nameHex, 'value': value.value,
             'dataType': value.dataType, 'rawData': value.rawData},
        ],
      },
    };
  }
}
