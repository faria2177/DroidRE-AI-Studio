import 'package:flutter/material.dart';

import '../models/apk_report.dart';
import '../services/resource_inspector.dart';

class ResourceExplorerTab extends StatefulWidget {
  const ResourceExplorerTab({super.key, required this.report});

  final ApkReport report;

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
                return SingleChildScrollView(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Packages: ${data.packageCount}'),
                    Text('Top-level string pools: ${data.stringPoolChunks}'),
                    const SizedBox(height: 10),
                    for (final name in data.packages) SelectableText(name),
                    const SizedBox(height: 10),
                    const Text('Only table headers and package names are decoded. '
                      'Resource IDs, values and binary XML references require deeper parsing.'),
                  ],
                ));
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
          const Text('Tap a file to inspect its header, text, or supported image. '
            'Binary XML and resource values are not yet decompiled.'),
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
