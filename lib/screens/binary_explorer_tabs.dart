import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/apk_report.dart';
import '../services/dex_inspector.dart';
import '../services/dex_call_graph.dart';
import '../services/elf_inspector.dart';

class DexBrowserTab extends StatefulWidget {
  const DexBrowserTab({super.key, required this.report, this.onExplainCode});

  final ApkReport report;
  final ValueChanged<String>? onExplainCode;

  @override
  State<DexBrowserTab> createState() => _DexBrowserTabState();
}

class _DexBrowserTabState extends State<DexBrowserTab> {
  String? selected;
  String query = '';
  Future<DexFileSummary>? task;

  void _showPseudocode(DexMethodSummary method, String dexFile) {
    final future = DexInspector.pseudocodeEntryMethod(
        widget.report.localPath, dexFile, method);
    showDialog<void>(context: context, builder: (context) =>
      FutureBuilder<String>(future: future, builder: (context, snapshot) =>
        AlertDialog(
          title: Text('Java-like pseudocode: ${method.name}'),
          content: SizedBox(width: 650, child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
                const Text('Approximation only: not Java source, compilable '
                    'output, or verified control-flow reconstruction.'),
                const SizedBox(height: 10),
                if (!snapshot.hasData && !snapshot.hasError)
                  const LinearProgressIndicator(),
                if (snapshot.hasError)
                  Text('Pseudocode unavailable: ${snapshot.error}'),
                if (snapshot.hasData)
                  SelectableText(snapshot.data!, style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 12)),
              ]),
          )),
          actions: [
            if (snapshot.hasData)
              TextButton.icon(onPressed: () async {
                await Clipboard.setData(ClipboardData(text: snapshot.data!));
              }, icon: const Icon(Icons.copy), label: const Text('Copy')),
            if (snapshot.hasData && widget.onExplainCode != null)
              TextButton.icon(onPressed: () {
                Navigator.pop(context);
                widget.onExplainCode!('Review this approximate Java-like '
                    'pseudocode against its Dalvik origin. Mark every inference '
                    'and uncertainty; it is NOT decompiled source.\n\n'
                    '${snapshot.data!.length > 18000
                        ? snapshot.data!.substring(0, 18000)
                        : snapshot.data!}');
              }, icon: const Icon(Icons.auto_awesome),
                label: const Text('Explain with AI')),
            TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
          ],
        )));
  }

  void _showMultiDexGraph(DexMethodSummary method, String dexFile,
      DexFileSummary currentSummary) {
    final future = DexCallGraph.scanApk(widget.report.localPath,
        widget.report.dexFiles, dexFile, method.methodIdIndex);
    showDialog<void>(context: context, builder: (context) =>
      AlertDialog(
        title: const Text('Multi-DEX Call Graph'),
        content: SizedBox(width: 670, height: MediaQuery.sizeOf(context).height * 0.55,
          child: FutureBuilder<DexGraphResult>(future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Call graph unavailable: ${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final graph = snapshot.data!;
              final sections = <(String, List<DexCallEdge>, bool)>[
                ('Direct callers', graph.directIncoming, true),
                ('Direct calls', graph.directOutgoing, false),
                ('Callers two hops away', graph.secondLevelIncoming, true),
                ('Calls two hops away', graph.secondLevelOutgoing, false),
              ];
              return ListView(children: [
                SelectableText(graph.root, style: const TextStyle(
                    fontFamily: 'monospace')),
                const SizedBox(height: 8),
                Text('Scanned ${graph.scannedDexFiles} DEX files and '
                    '${graph.scannedMethods} method bodies. '
                    '${graph.skippedMethods} unsupported method bodies; '
                    '${graph.skippedDexFiles} skipped DEX files. '
                    '${graph.truncated ? 'Partial results (scan cap).' : 'Static references only.'}'),
                const SizedBox(height: 12),
                for (final section in sections) ...[
                  Text('${section.$1} (${section.$2.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (section.$2.isEmpty)
                    const Padding(padding: EdgeInsets.all(8),
                        child: Text('No matches in scanned code')),
                  for (final edge in section.$2.take(40))
                    Builder(builder: (context) {
                      final signature = section.$3 ? edge.caller : edge.callee;
                      final location = graph.declarations[signature];
                      return ListTile(
                        dense: true,
                        title: Text(signature, maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text('${edge.opcode} · '
                            '${location?.dexFile ?? 'external/other DEX'}'),
                        trailing: location == null ? null
                            : const Icon(Icons.open_in_new),
                        onTap: location == null ? null : () async {
                          Navigator.pop(context);
                          try {
                            final summary = location.dexFile == dexFile
                                ? currentSummary : await DexInspector.inspectEntry(
                                    widget.report.localPath, location.dexFile);
                            if (mounted) {
                              _showMethod(location.method, location.dexFile, summary);
                            }
                          } catch (error) {
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(content: Text('Unable to open method: $error')));
                            }
                          }
                        },
                      );
                    }),
                  const Divider(height: 22),
                ],
              ]);
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Close'))],
      ));
  }

  void _showCallers(DexMethodSummary method, String dexFile,
      DexFileSummary summary) {
    final task = DexInspector.findCallersEntry(widget.report.localPath,
        dexFile, summary.classes, method.methodIdIndex);
    showDialog<void>(context: context, builder: (context) =>
      AlertDialog(
        title: Text('Callers of ${method.name}'),
        content: SizedBox(width: 620, child: FutureBuilder<DexCallerResult>(
          future: task,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('XREF scan failed: ${snapshot.error}');
            }
            if (!snapshot.hasData) {
              return const LinearProgressIndicator();
            }
            final result = snapshot.data!;
            return SizedBox(height: 410, child: Column(children: [
              Text('Scanned ${result.scanned} indexed methods; '
                  '${result.skipped} methods could not be fully decoded. '
                  '${result.truncated ? 'Results are incomplete.' : 'Index-based scan only.'}'),
              const SizedBox(height: 12),
              Expanded(child: result.callers.isEmpty
                  ? const Center(child: Text('No callers found in scanned methods'))
                  : ListView.builder(
                      itemCount: result.callers.length,
                      itemBuilder: (context, index) {
                        final caller = result.callers[index];
                        return ListTile(
                          title: Text(caller.name),
                          subtitle: Text('${caller.ownerName}\n${caller.prototype}'),
                          isThreeLine: true,
                          trailing: const Icon(Icons.open_in_new),
                          onTap: () {
                            Navigator.pop(context);
                            _showMethod(caller, dexFile, summary);
                          },
                        );
                      },
                    )),
            ]));
          },
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Close'))],
      ));
  }

  void _showMethod(DexMethodSummary method, String dexFile,
      DexFileSummary summary) {
    final task = DexInspector.analyzeEntryMethod(
      widget.report.localPath, dexFile, method);
    showDialog<void>(context: context, builder: (context) =>
      FutureBuilder<DexMethodAnalysis>(future: task, builder: (context, snapshot) {
        final code = snapshot.data?.text ?? method.smaliPreview;
        final refs = snapshot.data?.references ?? const <DexCodeReference>[];
        return AlertDialog(
          title: Text('${method.name}${method.prototype}',
            maxLines: 2, overflow: TextOverflow.ellipsis),
          content: SizedBox(width: 620, child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Read-only Dalvik instructions and decoded operands. '
                    'This viewer does not reconstruct Java or guarantee '
                    'assemblable Smali.'),
                const SizedBox(height: 8),
                if (snapshot.connectionState != ConnectionState.done)
                  const LinearProgressIndicator(),
                if (snapshot.hasError)
                  Text('Decoder limitation: ${snapshot.error}\n'
                    'Showing bounded raw code-unit fallback.'),
                Text('Code offset: 0x${method.codeOffset.toRadixString(16)}'
                  ' · Code units: ${method.instructionCount}'),
                const SizedBox(height: 10),
                SelectableText(code,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: snapshot.connectionState != ConnectionState.done
                      ? null : () {
                    Navigator.pop(context);
                    _showPseudocode(method, dexFile);
                  },
                  icon: const Icon(Icons.integration_instructions_outlined),
                  label: const Text('View Java-like pseudocode'),
                ),
                if (refs.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Referenced symbols (${refs.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Text('Tap a method to open its declaration when indexed '
                      'in the selected DEX. Other references are read-only.'),
                  for (final reference in refs.take(40))
                    ListTile(
                      dense: true,
                      title: Text(reference.label, maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text('${reference.kind} #${reference.index}'),
                      trailing: reference.kind == 'method'
                          ? const Icon(Icons.arrow_forward) : null,
                      onTap: reference.kind != 'method' ? null : () {
                        DexMethodSummary? target;
                        for (final klass in summary.classes) {
                          for (final candidate in klass.details) {
                            if (candidate.methodIdIndex == reference.index) {
                              target = candidate;
                              break;
                            }
                          }
                          if (target != null) {
                            break;
                          }
                        }
                        if (target == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Method body is not indexed '
                                'in this DEX; the symbol is still resolved above.')));
                          return;
                        }
                        Navigator.pop(context);
                        _showMethod(target, dexFile, summary);
                      },
                    ),
                  if (refs.length > 40)
                    const Text('Showing the first 40 referenced symbols'),
                ],
              ],
            ),
          )),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (context.mounted) Navigator.pop(context);
              },
              label: const Text('Copy'),
            ),
            if (widget.onExplainCode != null)
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onExplainCode!(
                    'Analyze this Dalvik method '
                    '${method.ownerName}.${method.name}${method.prototype}. '
                    'Structure the answer as: (1) behavior summary, '
                    '(2) step-by-step evidence with instruction offsets, '
                    '(3) called methods and accessed fields, '
                    '(4) possible risks, (5) uncertainties and suggested '
                    'next inspection targets. Do not invent source code.\n\n'
                    'Resolved references:\n'
                    '${refs.take(50).map((ref) => '${ref.kind}: ${ref.label}').join('\n')}\n\n'
                    '${code.length > 18000 ? code.substring(0, 18000) : code}',
                  );
                },
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Explain with AI'),
              ),
            if (method.methodIdIndex >= 0)
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showCallers(method, dexFile, summary);
                },
                icon: const Icon(Icons.call_received),
                label: const Text('Find callers'),
              ),
            if (method.methodIdIndex >= 0)
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showMultiDexGraph(method, dexFile, summary);
                },
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Call graph'),
              ),
            TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
          ],
        );
      }),
    );
  }

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
              const Text('DEX 035–040 · limit 32 MiB per file. '
                  'Tap a method to decode its Dalvik instructions. '
                  'Unknown opcodes fall back to raw units.'),
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
                        for (final method in item.details)
                          ListTile(
                            dense: true,
                            title: Text(method.name),
                            subtitle: Text(method.prototype),
                            trailing: const Icon(Icons.code),
                            onTap: () => _showMethod(method, selectedFile, summary),
                          ),
                        for (final name in item.methods.skip(item.details.length))
                          ListTile(dense: true, title: Text(name),
                            subtitle: const Text('Name only (detail preview limit reached)')),
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
