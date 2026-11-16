import 'dart:convert';
import 'dart:typed_data' as typed;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/apk_report.dart';
import '../services/resource_inspector.dart';
import '../services/arsc_reference_resolver.dart';
import '../services/arsc_style_resolver.dart';
import '../services/arsc_inherited_style_inspector.dart';
import '../services/arsc_variant_inspector.dart';
import '../services/arsc_variant_diff_inspector.dart';
import '../services/arsc_variant_reference_inspector.dart';
import '../services/arsc_variant_report_exporter.dart';
import '../services/arsc_resource_variant_filter.dart';

class ResourceExplorerTab extends StatefulWidget {
  const ResourceExplorerTab({super.key, required this.report,
      this.onExplainCode});

  final ApkReport report;
  final ValueChanged<String>? onExplainCode;

  @override
  State<ResourceExplorerTab> createState() => _ResourceExplorerTabState();
}

class _ResourceExplorerTabState extends State<ResourceExplorerTab> {
  String filter = '';
  String category = 'All';

  @override
  void didUpdateWidget(covariant ResourceExplorerTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report.id != widget.report.id) {
      filter = '';
      category = 'All';
    }
  }

  String _category(String name) {
    if (name == 'resources.arsc') return 'Compiled table';
    if (name == 'AndroidManifest.xml') return 'Manifest';
    if (name.startsWith('assets/')) return 'assets';
    final segments = name.split('/');
    return segments.length > 1 ? segments[1] : 'Other';
  }

  void _inspect(String name) {
    final future = name == 'resources.arsc'
        ? ResourceInspector.inspectTable(widget.report.localPath)
        : ResourceInspector.preview(widget.report.localPath, name);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: 600,
          child: FutureBuilder<Object>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Cannot inspect resource: ${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              if (data is ResourceTableSummary) {
                return SizedBox(
                  height: 440,
                  child: _CompiledTableViewer(summary: data),
                );
              }
              final preview = data as ResourcePreview;
              return SingleChildScrollView(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${preview.bytes.length} bytes loaded'),
                  if (preview.isImage) ...[
                    const SizedBox(height: 8),
                    Image.memory(preview.bytes, height: 220,
                      errorBuilder: (_, _, _) => const Text('Image preview unavailable')),
                  ],
                  if (preview.textContent != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(preview.textContent!,
                      style: const TextStyle(fontFamily: 'monospace')),
                  ],
                  if (preview.decodedXml != null) ...[
                    const SizedBox(height: 8),
                    Text('Decoded Android Binary XML: '
                        '${preview.xmlElementCount} elements, '
                        '${preview.xmlAttributeCount} attributes'),
                    const SizedBox(height: 8),
                    SelectableText(preview.decodedXml!.length > 50000
                        ? '${preview.decodedXml!.substring(0, 50000)}\n'
                          '[Viewer truncated at 50,000 characters]'
                        : preview.decodedXml!,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                    if (widget.onExplainCode != null)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onExplainCode!(
                            'Explain this Android XML resource ($name), its UI '
                            'hierarchy, attributes and potential issues. '
                            'Only infer from this snippet:\n\n'
                            '${preview.decodedXml!.length > 18000
                                ? preview.decodedXml!.substring(0, 18000)
                                : preview.decodedXml!}',
                          );
                        },
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Explain XML with AI'),
                      ),
                  ],
                  if (preview.xmlDecodeError != null)
                    Text('Binary XML could not be decoded: '
                        '${preview.xmlDecodeError}'),
                  const SizedBox(height: 8),
                  const Text('Hex preview (first 64 bytes):'),
                  SelectableText(preview.hexHeader,
                    style: const TextStyle(fontFamily: 'monospace')),
                ],
              ));
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.report.entries.where((entry) => entry.isFile &&
        (entry.name.startsWith('res/') ||
            entry.name.startsWith('assets/') ||
            entry.name == 'AndroidManifest.xml' ||
            entry.name == 'resources.arsc')).toList();
    final categoryNames = entries.map((entry) => _category(entry.name))
        .toSet().toList()..sort();
    final categories = <String>['All', ...categoryNames];
    final selectedCategory = categories.contains(category) ? category : 'All';
    final matches = entries.where((entry) =>
        (selectedCategory == 'All' ||
            _category(entry.name) == selectedCategory) &&
        entry.name.toLowerCase().contains(filter.toLowerCase())).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Text('${entries.length} indexed resource and asset files · local only'),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search resource paths', prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => filter = value),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('${widget.report.id}:$selectedCategory'),
            initialValue: selectedCategory,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Resource category', border: OutlineInputBorder()),
            items: categories.map((value) => DropdownMenuItem(
              value: value, child: Text(value))).toList(),
            onChanged: (value) => setState(() => category = value ?? 'All'),
          ),
          const SizedBox(height: 6),
          const Text('Tap a file to inspect text, images, Android XML or '
              'simple compiled resource IDs and values.'),
        ]),
      ),
      Expanded(child: ListView.builder(
        itemCount: matches.length,
        itemBuilder: (context, index) {
          final entry = matches[index];
          return ListTile(
            dense: true,
            leading: Icon(entry.name == 'resources.arsc'
                ? Icons.table_chart_outlined
                : Icons.insert_drive_file_outlined),
            title: Text(entry.name),
            subtitle: Text('${entry.size} bytes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _inspect(entry.name),
          );
        },
      )),
    ]);
  }
}

class _CompiledTableViewer extends StatefulWidget {
  const _CompiledTableViewer({required this.summary});
  final ResourceTableSummary summary;

  @override
  State<_CompiledTableViewer> createState() => _CompiledTableViewerState();
}

class _CompiledTableViewerState extends State<_CompiledTableViewer> {
  String query = '';
  ArscResourceFilter configFilter = ArscResourceFilter.all;

  void _showStyleComparison(
      BuildContext context, ArscInheritedStyleReport report) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Inherited style attribute preview'),
        content: SizedBox(
          width: 660,
          height: 470,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${report.attributes.length} raw attribute IDs · '
                  'chain: ${report.trace.status.name}'
                  '${report.partial ? ' · partial preview' : ''}'),
              const SizedBox(height: 6),
              SelectableText(report.trace.description),
              if (report.warnings.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(report.warnings.join(' · ')),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Root-to-child decoded map precedence only. '
                    'Not device-selected effective theme values; unresolved '
                    'references, overlays and framework attributes remain raw.'),
              ),
              Expanded(
                child: report.attributes.isEmpty
                    ? const Center(child: Text('No known map attributes'))
                    : ListView.builder(
                        itemCount: report.attributes.length,
                        itemBuilder: (context, index) {
                          final item = report.attributes[index];
                          return ListTile(
                            dense: true,
                            title: SelectableText(
                              '${item.label} = ${item.value}'),
                            subtitle: SelectableText([
                              '${item.kind.name} · from ${item.sourceName}',
                              if (item.shadowedValue != null)
                                'Shadows ${item.shadowedSource}: '
                                    '${item.shadowedValue}',
                              if (item.kind == ArscStyleAttributeKind.uncertain)
                                'A closer truncated bag may contain '
                                    'an unseen override',
                            ].join('\n')),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }



  Future<void> _saveComparison(
    ArscVariantComparison comparison, {
    required bool csv,
  }) async {
    final report = ArscVariantReportExporter.build(
        comparison, widget.summary.values);
    final filename = '${report.fileStem}.${csv ? 'csv' : 'json'}';
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save resource comparison',
        fileName: filename,
        bytes: typed.Uint8List.fromList(
          utf8.encode(csv ? report.toCsv() : report.toJson()),
        ),
      );
      if (!mounted) {
        return;
      }
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saved $filename'
              '${report.truncated ? ' (partial report)' : ''}'),
        ));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Export failed: $error'),
      ));
    }
  }

  void _showConfigurations(
      BuildContext context, ArscVariantComparison comparison) {
    final baseline = ArscVariantDiffInspector.baseline(comparison);
    final references = ArscVariantReferenceInspector(widget.summary.values);
    final defaultCount = comparison.variants
        .where((entry) => entry.configuration?.isDefault == true)
        .length;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Resource configurations · ${comparison.resourceName}'),
        content: SizedBox(
          width: 660,
          height: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${comparison.variants.length} decoded configurations · '
                  '${comparison.valuesDiffer ? 'Different raw values' : 'Matching raw values'}'),
              const SizedBox(height: 4),
              SelectableText('Comparison baseline: '
                  '${baseline.configuration?.label ?? 'config chunk ${baseline.config}'}'
                  '${defaultCount == 1 ? ' (unique default)' : ' (first decoded; not selected by Android)'}'),
              if (comparison.duplicateQualifiers)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Multiple decoded variants have matching '
                      'qualifier labels; Android selection is not inferred.'),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Expanded locale tags and field-level raw '
                    'differences are compared only within decoded ARSC '
                    'entries. Runtime resource matching, locale fallback, '
                    'overlays and configuration priority are not evaluated.'),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: comparison.variants.length,
                  itemBuilder: (context, index) {
                    final entry = comparison.variants[index];
                    final detail = ArscVariantDiffInspector.compare(
                        baseline, entry);
                    final referenceChanges = references.compare(
                        baseline, entry);
                    return ExpansionTile(
                      key: ValueKey('${comparison.resourceId}:${entry.config}'),
                      title: Text(entry.configuration?.label ??
                          'Unknown config chunk ${entry.config}'),
                      subtitle: Text('${entry.value} · '
                          '${detail.changedFields} changed fields'
                          '${detail.partial ? ' · partial' : ''}'),
                      children: [
                        for (final warning in detail.warnings)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: Text(warning),
                          ),
                        for (final reference in referenceChanges)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SelectableText(
                                'Reference ${reference.change.name}: '
                                '${reference.field}\n'
                                'Baseline: ${reference.before ?? '(none)'}\n'
                                'Variant: ${reference.after ?? '(none)'}',
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 12),
                              ),
                            ),
                          ),
                        for (final field in detail.fields)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SelectableText(
                                '${field.change.name}: ${field.field}\n'
                                'Baseline: ${field.before ?? '(not present)'}\n'
                                'Variant: ${field.after ?? '(not present)'}',
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 12),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await _saveComparison(comparison, csv: true);
            },
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Save CSV'),
          ),
          TextButton.icon(
            onPressed: () async {
              await _saveComparison(comparison, csv: false);
            },
            icon: const Icon(Icons.data_object),
            label: const Text('Save JSON'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final lowerQuery = query.toLowerCase();
    final resolver = ArscReferenceResolver(summary.values);
    final styles = ArscStyleResolver(summary.values);
    final variants = ArscVariantInspector(summary.values);
    final filters = ArscResourceVariantFilter(summary.values);
    final matches = summary.values.where((entry) =>
      filters.matches(entry, configFilter) && (
      entry.idHex.toLowerCase().contains(lowerQuery) ||
      entry.name.toLowerCase().contains(lowerQuery) ||
      entry.value.toLowerCase().contains(lowerQuery) ||
      (resolver.trace(entry)?.description.toLowerCase().contains(lowerQuery) ?? false) ||
      (styles.trace(entry)?.description.toLowerCase().contains(lowerQuery) ?? false) ||
      (entry.bag?.items.any((item) =>
          styles.attributeLabel(item.nameId).toLowerCase().contains(lowerQuery) ||
          item.value.toLowerCase().contains(lowerQuery)) ?? false) ||
      (ArscInheritedStyleInspector.inspect(entry, styles)
          ?.attributes.any((item) =>
              item.label.toLowerCase().contains(lowerQuery) ||
              item.value.toLowerCase().contains(lowerQuery)) ?? false) ||
      (entry.configuration?.qualifiers.toLowerCase().contains(lowerQuery) ?? false)
    )).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Packages: ${summary.packageCount} · '
           'Top-level pools: ${summary.stringPoolChunks}'),
      for (final name in summary.packages)
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 6),
      Text('${summary.values.length} simple/bag entries decoded · '
           '${summary.scannedSlots} index slots inspected'
           '${summary.valuesTruncated ? ' · partial results' : ''}'),
      const SizedBox(height: 6),
      TextField(
        decoration: const InputDecoration(
          labelText: 'Filter ID, type/name or value',
          prefixIcon: Icon(Icons.search),
          isDense: true,
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState(() => query = value),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<ArscResourceFilter>(
        key: ValueKey('configuration-filter:${configFilter.name}'),
        initialValue: configFilter,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Resource configuration filter',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: ArscResourceFilter.values.map((mode) {
          final label = switch (mode) {
            ArscResourceFilter.all => 'All decoded entries',
            ArscResourceFilter.variants => 'Multiple configurations',
            ArscResourceFilter.changed => 'Different values',
            ArscResourceFilter.night => 'Night mode',
            ArscResourceFilter.day => 'Not-night mode',
            ArscResourceFilter.localized => 'Locale-specific',
            ArscResourceFilter.density => 'Density-specific',
            ArscResourceFilter.referenceDifferences => 'Reference differences',
          };
          return DropdownMenuItem(value: mode, child: Text(label));
        }).toList(),
        onChanged: (value) => setState(() =>
            configFilter = value ?? ArscResourceFilter.all),
      ),
      if (summary.valueWarnings.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(summary.valueWarnings.join(' · '),
            maxLines: 3, overflow: TextOverflow.ellipsis),
        ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text('References and style-parent chains are traced within '
          'decoded entries only. Attribute labels are shown only when an '
          '@attr entry is present. Missing parents may exist outside this '
          'preview. Tap a style comparison icon to inspect known raw '
          'attribute precedence. Configuration comparisons can be saved '
          'as JSON or UTF-8 CSV. Names and reference IDs are preview-only; '
          'runtime selection and overlays remain unsupported.'),
      ),
      Expanded(child: matches.isEmpty
        ? const Center(child: Text('No matching decoded values'))
        : ListView.builder(
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final entry = matches[index];
              final reference = resolver.trace(entry);
              final style = styles.trace(entry);
              final inheritance =
                  ArscInheritedStyleInspector.inspect(entry, styles);
              final configComparison = variants.comparisonFor(entry);
              return ListTile(
                dense: true,
                title: SelectableText('${entry.idHex}  ${entry.name}',
                  style: const TextStyle(fontFamily: 'monospace')),
                trailing: inheritance == null && configComparison == null
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (configComparison != null)
                            IconButton(
                              tooltip: 'Compare resource configurations',
                              icon: const Icon(Icons.tune),
                              onPressed: () => _showConfigurations(
                                  context, configComparison),
                            ),
                          if (inheritance != null)
                            IconButton(
                              tooltip: 'Compare inherited style attributes',
                              icon: const Icon(Icons.compare_arrows),
                              onPressed: () =>
                                  _showStyleComparison(context, inheritance),
                            ),
                        ],
                      ),
                subtitle: SelectableText([
                  '${entry.value}  (${entry.configuration?.label ?? 'config chunk ${entry.config}'})',
                  if (reference != null)
                    'Reference: ${reference.description}',
                  if (style != null)
                    'Style parent chain (${style.status.name}): '
                      '${style.description}',
                  if (configComparison != null)
                    '${configComparison.variants.length} configuration variants',
                  if (inheritance != null)
                    '${inheritance.attributes.length} compared attribute IDs'
                    '${inheritance.partial ? ' · partial preview' : ''}',
                  if (entry.bag != null) ...[
                    'Bag parent: ${entry.bag!.parentHex} · '
                      '${entry.bag!.totalItems} raw map items'
                      '${entry.bag!.truncated ? ' (preview limited)' : ''}',
                    for (final item in entry.bag!.items)
                      '${styles.attributeLabel(item.nameId)} = ${item.value}',
                  ],
                ].join('\n')),
              );
            },
          )),
    ]);
  }
}
