import 'package:flutter/material.dart';

import '../models/apk_report.dart';
import '../services/dex_inspector.dart';
import '../services/elf_inspector.dart';

class DexBrowserTab extends StatefulWidget {
  const DexBrowserTab({super.key, required this.report});

  final ApkReport report;

  @override
  State<DexBrowserTab> createState() => _DexBrowserTabState();
}

class _DexBrowserTabState extends State<DexBrowserTab> {
  String? selected;
  String query = '';
  Future<DexFileSummary>? task;

  @override
  void didUpdateWidget(covariant DexBrowserTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report.id != widget.report.id) {
      selected = null;
      query = '';
      task = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.report.dexFiles;
    if (files.isEmpty) {
      return const Center(child: Text('No DEX files in this package'));
    }
    final selectedFile = selected != null && files.contains(selected)
        ? selected!
        : files.first;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Read-only DEX class and method explorer'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('${widget.report.id}:$selectedFile'),
                initialValue: selectedFile,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'DEX file', border: OutlineInputBorder()),
                items: files.map((name) => DropdownMenuItem(
                  value: name, child: Text(name, overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (value) => setState(() {
                  selected = value;
                  task = null;
                  query = '';
                }),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: task == null ? () => setState(() {
                  task = DexInspector.inspectEntry(widget.report.localPath, selectedFile);
                }) : null,
                icon: const Icon(Icons.manage_search),
                label: Text(task == null ? 'Inspect classes' : 'Loaded / loading'),
              ),
              const Text('Supports standard DEX 035–040, up to 32 MiB per file. '
                  'No Smali or Java source reconstruction.'),
            ],
          ),
        ),
        if (task == null)
          const Expanded(child: Center(child: Text('Select a DEX file and tap Inspect classes')))
        else
          Expanded(child: FutureBuilder<DexFileSummary>(
            future: task,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _ErrorPanel(error: snapshot.error.toString(), onRetry: () =>
                  setState(() => task = null));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final summary = snapshot.data!;
              final matches = summary.classes.where((item) =>
                item.name.toLowerCase().contains(query.toLowerCase())).toList();
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('DEX ${summary.version} · ${summary.classes.length} classes · '
                    '${summary.methodIdCount} method IDs'),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Filter class names',
                      prefixIcon: Icon(Icons.search), border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => query = value),
                  ),
                ),
                Expanded(child: ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final item = matches[index];
                    return Card(child: ExpansionTile(
                      title: Text(item.name),
                      subtitle: Text('${item.methodCount} declared methods'),
                      children: [
                        for (final name in item.methods)
                          ListTile(dense: true, title: SelectableText(name)),
                        if (item.methodCount > item.methods.length)
                          ListTile(title: Text('First ${item.methods.length} methods shown')),
                        if (item.methodCount == 0)
                          const ListTile(title: Text('No declared methods')),
                      ],
                    ));
                  },
                )),
              ]);
            },
          )),
      ],
    );
  }
}

class ElfBrowserTab extends StatefulWidget {
  const ElfBrowserTab({super.key, required this.report});

  final ApkReport report;

  @override
  State<ElfBrowserTab> createState() => _ElfBrowserTabState();
}

class _ElfBrowserTabState extends State<ElfBrowserTab> {
  String? selected;
  Future<ElfSummary>? task;

  @override
  void didUpdateWidget(covariant ElfBrowserTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report.id != widget.report.id) {
      selected = null;
      task = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.report.nativeLibraries;
    if (files.isEmpty) {
      return const Center(child: Text('No native libraries found'));
    }
    final selectedFile = selected != null && files.contains(selected)
        ? selected!
        : files.first;
    return ListView(padding: const EdgeInsets.all(14), children: [
      const Text('Read-only ELF header inspector'),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: ValueKey('${widget.report.id}:$selectedFile'),
        initialValue: selectedFile,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Native .so file', border: OutlineInputBorder(),
        ),
        items: files.map((name) => DropdownMenuItem(
          value: name, child: Text(name, overflow: TextOverflow.ellipsis),
        )).toList(),
        onChanged: (value) => setState(() {
          selected = value;
          task = null;
        }),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: task == null ? () => setState(() {
          task = ElfInspector.inspectEntry(widget.report.localPath, selectedFile);
        }) : null,
        icon: const Icon(Icons.memory),
        label: Text(task == null ? 'Inspect ELF header' : 'Loaded / loading'),
      ),
      const SizedBox(height: 8),
      const Text('Header-only: architecture, file type, entry point and table counts. '
        'No symbols, disassembly or code execution. Limit: 80 MiB per library.'),
      if (task != null)
        FutureBuilder<ElfSummary>(future: task, builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorPanel(error: snapshot.error.toString(), onRetry: () =>
              setState(() => task = null));
          }
          if (!snapshot.hasData) {
            return const Padding(padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()));
          }
          final elf = snapshot.data!;
          final attributes = <String, String>{
            'ELF class': '${elf.bits}-bit',
            'Byte order': elf.byteOrder,
            'Architecture': elf.machine,
            'Object type': elf.fileType,
            'Entry point': elf.entryPoint,
            'Program headers': '${elf.programHeaders}',
            'Section headers': '${elf.sectionHeaders}',
          };
          return Column(children: [
            for (final entry in attributes.entries)
              Card(child: ListTile(
                title: Text(entry.key), subtitle: SelectableText(entry.value),
              )),
          ]);
        }),
    ]);
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(18),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.warning_amber, color: Colors.amber),
      const SizedBox(height: 8),
      Text(error, textAlign: TextAlign.center),
      TextButton(onPressed: onRetry, child: const Text('Choose another file')),
    ]),
  ));
}
