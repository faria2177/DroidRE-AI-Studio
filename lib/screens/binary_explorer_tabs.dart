import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/apk_report.dart';
import '../services/dex_inspector.dart';
import '../services/dex_call_graph.dart';
import '../services/dex_method_pager.dart';
import '../services/dex_method_search.dart';
import '../services/elf_inspector.dart';
import '../services/elf_symbol_inspector.dart';
import '../services/elf_dependency_inspector.dart';
import '../services/elf_section_inspector.dart';
import '../services/native_dependency_graph_inspector.dart';

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
  Future<DexMethodSearchResult>? methodSearchTask;
  final methodSearchController = TextEditingController();
  String? methodSearchError;

  void _searchMethods(String dexFile) {
    final term = methodSearchController.text.trim();
    if (term.isEmpty) {
      setState(() {
        methodSearchTask = null;
        methodSearchError = null;
      });
      return;
    }
    if (term.length < 2) {
      setState(() {
        methodSearchTask = null;
        methodSearchError = 'Enter at least two characters.';
      });
      return;
    }
    setState(() {
      methodSearchError = null;
      methodSearchTask = DexMethodSearch.searchEntry(
          widget.report.localPath, dexFile, term);
    });
  }

  @override
  void dispose() {
    methodSearchController.dispose();
    super.dispose();
  }

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
                for (final warning in graph.warnings.take(3))
                  Text('Skipped: $warning', style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
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
      methodSearchTask = null;
      methodSearchError = null;
      methodSearchController.clear();
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
                  methodSearchTask = null;
                  methodSearchError = null;
                  methodSearchController.clear();
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    Expanded(child: TextField(
                      controller: methodSearchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: 'Search declared methods',
                        hintText: 'onCreate, encrypt, decode...',
                        prefixIcon: const Icon(Icons.code),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: 'Clear method search',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            methodSearchController.clear();
                            setState(() {
                              methodSearchTask = null;
                              methodSearchError = null;
                            });
                          },
                        ),
                      ),
                      onSubmitted: (_) => _searchMethods(selectedFile),
                      onChanged: (_) {
                        if (methodSearchTask != null || methodSearchError != null) {
                          setState(() {
                            methodSearchTask = null;
                            methodSearchError = null;
                          });
                        }
                      },
                    )),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Find methods',
                      onPressed: () => _searchMethods(selectedFile),
                      icon: const Icon(Icons.search),
                    ),
                  ]),
                ),
                if (methodSearchError != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(methodSearchError!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                Expanded(child: methodSearchTask == null
                  ? ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final item = matches[index];
                        return _DexClassMethodTile(
                          key: ValueKey('${widget.report.id}:$selectedFile:${item.classDefIndex}'),
                          klass: item,
                          apkPath: widget.report.localPath,
                          dexFile: selectedFile,
                          onOpen: (method) => _showMethod(method, selectedFile, summary),
                        );
                      },
                    )
                  : FutureBuilder<DexMethodSearchResult>(
                      future: methodSearchTask,
                      builder: (context, result) {
                        if (result.hasError) {
                          return _ErrorPanel(
                            error: 'Method search failed: ${result.error}',
                            onRetry: () => _searchMethods(selectedFile),
                          );
                        }
                        if (!result.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final found = result.data!;
                        return Column(children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              '${found.methods.length} matching declared methods · '
                              '${found.scannedMethods} methods scanned',
                            ),
                          ),
                          if (found.truncated)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'Results limited for this scan. Narrow the query '
                                'to find additional methods.',
                              ),
                            ),
                          Expanded(
                            child: found.methods.isEmpty
                              ? const Center(child: Text('No matching declared methods'))
                              : ListView.builder(
                                  itemCount: found.methods.length,
                                  itemBuilder: (context, index) {
                                    final method = found.methods[index];
                                    return ListTile(
                                      title: Text(method.name),
                                      subtitle: Text(
                                        '${method.ownerName}\n${method.prototype}',
                                      ),
                                      trailing: const Icon(Icons.code),
                                      onTap: () => _showMethod(
                                          method, selectedFile, summary),
                                    );
                                  },
                                ),
                          ),
                        ]);
                      },
                    )),
              ]);
            },
          )),
      ],
    );
  }
}


class _DexClassMethodTile extends StatefulWidget {
  const _DexClassMethodTile({
    super.key,
    required this.klass,
    required this.apkPath,
    required this.dexFile,
    required this.onOpen,
  });

  final DexClassSummary klass;
  final String apkPath;
  final String dexFile;
  final ValueChanged<DexMethodSummary> onOpen;

  @override
  State<_DexClassMethodTile> createState() => _DexClassMethodTileState();
}

class _DexClassMethodTileState extends State<_DexClassMethodTile> {
  late List<DexMethodSummary> _methods;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _methods = List<DexMethodSummary>.of(widget.klass.details);
  }

  @override
  void didUpdateWidget(covariant _DexClassMethodTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apkPath != widget.apkPath ||
        oldWidget.dexFile != widget.dexFile ||
        oldWidget.klass.classDefIndex != widget.klass.classDefIndex) {
      _methods = List<DexMethodSummary>.of(widget.klass.details);
      _loading = false;
      _error = null;
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _methods.length >= widget.klass.methodCount) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await DexMethodPager.loadEntry(
        widget.apkPath,
        widget.dexFile,
        widget.klass,
        start: _methods.length,
      );
      if (!mounted) return;
      if (page.isEmpty) {
        setState(() => _error = 'No additional methods were returned.');
      } else {
        setState(() => _methods.addAll(page));
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: Text(widget.klass.name),
      subtitle: Text(
        '${_methods.length} of ${widget.klass.methodCount} method details loaded',
      ),
      children: [
        for (final method in _methods)
          ListTile(
            dense: true,
            title: Text(method.name),
            subtitle: Text(method.prototype),
            trailing: const Icon(Icons.code),
            onTap: () => widget.onOpen(method),
          ),
        if (_error != null)
          ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text(_error!),
          ),
        if (_methods.length < widget.klass.methodCount)
          ListTile(
            leading: _loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more),
            title: Text(_methods.isEmpty
                ? 'Load method details'
                : 'Load more methods'),
            subtitle: const Text('Read the next 100 methods on demand'),
            onTap: _loading ? null : () => _loadMore(),
          ),
        if (widget.klass.methodCount == 0)
          const ListTile(title: Text('No declared methods')),
      ],
    ),
  );
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
  Future<ElfSymbolReport>? symbolsTask;
  Future<ElfDependencyReport>? dependencyTask;
  Future<ElfSectionReport>? sectionsTask;
  Future<NativeDependencyGraph>? graphTask;
  String sectionQuery = '';
  String symbolQuery = '';
  String symbolFilter = 'All';

  @override
  void didUpdateWidget(covariant ElfBrowserTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report.id != widget.report.id) {
      selected = null;
      task = null;
      symbolsTask = null;
      dependencyTask = null;
      sectionsTask = null;
      graphTask = null;
      sectionQuery = '';
      symbolQuery = '';
      symbolFilter = 'All';
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
      const Text('Read-only ELF header and symbol inspector'),
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
          symbolsTask = null;
          dependencyTask = null;
          sectionsTask = null;
          graphTask = null;
          sectionQuery = '';
          symbolQuery = '';
          symbolFilter = 'All';
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
      OutlinedButton.icon(
        onPressed: symbolsTask == null ? () => setState(() {
          symbolsTask = ElfSymbolInspector.inspectEntry(
              widget.report.localPath, selectedFile);
        }) : null,
        icon: const Icon(Icons.account_tree_outlined),
        label: Text(symbolsTask == null
            ? 'Inspect native symbols' : 'Symbols loaded / loading'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: dependencyTask == null ? () => setState(() {
          dependencyTask = ElfDependencyInspector.inspectEntry(
              widget.report.localPath, selectedFile);
        }) : null,
        icon: const Icon(Icons.link),
        label: Text(dependencyTask == null
            ? 'Inspect library dependencies' : 'Dependencies loaded / loading'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: sectionsTask == null ? () => setState(() {
          sectionsTask = ElfSectionInspector.inspectEntry(
              widget.report.localPath, selectedFile);
        }) : null,
        icon: const Icon(Icons.view_list_outlined),
        label: Text(sectionsTask == null
            ? 'Inspect ELF sections' : 'Sections loaded / loading'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: graphTask == null ? () => setState(() {
          graphTask = NativeDependencyGraphInspector.inspectEntry(
            widget.report.localPath, selectedFile,
            widget.report.nativeLibraries,
          );
        }) : null,
        icon: const Icon(Icons.hub_outlined),
        label: Text(graphTask == null
            ? 'Build ABI dependency graph' : 'Graph loaded / loading'),
      ),
      const SizedBox(height: 8),
      const Text('ELF32/ELF64 headers, sections, symbols, dependencies and '
          'same-ABI dependency graph. A declared DT_NEEDED dependency '
          'does not guarantee runtime availability. Read-only; no native '
          'disassembly or execution. Graph scans at most 64 libraries.'),
      if (graphTask != null)
        FutureBuilder<NativeDependencyGraph>(
          future: graphTask,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorPanel(
                error: 'Dependency graph inspection failed: ${snapshot.error}',
                onRetry: () => setState(() => graphTask = null),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return _NativeGraphViewer(
              key: ValueKey('${widget.report.id}:$selectedFile:graph'),
              graph: snapshot.data!,
            );
          },
        ),
      if (sectionsTask != null)
        FutureBuilder<ElfSectionReport>(
          future: sectionsTask,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorPanel(
                error: 'ELF section inspection failed: ${snapshot.error}',
                onRetry: () => setState(() => sectionsTask = null),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final report = snapshot.data!;
            final query = sectionQuery.toLowerCase();
            final matches = report.sections.where((section) {
              return section.name.toLowerCase().contains(query) ||
                  section.type.toLowerCase().contains(query) ||
                  section.flags.join(' ').toLowerCase().contains(query) ||
                  section.offsetHex.toLowerCase().contains(query);
            }).toList();

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('ELF sections',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text('${report.sections.length} of '
                         '${report.totalSections} headers decoded'
                         '${report.truncated ? ' · partial results' : ''}'),
                    if (report.warnings.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(report.warnings.join(' · ')),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Search section name, type or flags',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) =>
                          setState(() => sectionQuery = value),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 360,
                      child: matches.isEmpty
                          ? const Center(child: Text('No matching sections'))
                          : ListView.builder(
                              itemCount: matches.length,
                              itemBuilder: (context, index) {
                                final section = matches[index];
                                return ListTile(
                                  dense: true,
                                  title: SelectableText(
                                    '[#${section.index}] ${section.name} '
                                    '(${section.type})',
                                  ),
                                  subtitle: SelectableText(
                                    'Size: ${section.size} bytes · '
                                    'Offset: ${section.offsetHex} · '
                                    'VA: ${section.addressHex}\n'
                                    'Flags: ${section.flags.isEmpty ? 'none' : section.flags.join(', ')} · '
                                    'Alignment: ${section.alignment} · '
                                    '${section.fileBacked ? 'file-backed' : 'no file payload'}',
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      if (dependencyTask != null)
        FutureBuilder<ElfDependencyReport>(
          future: dependencyTask,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorPanel(
                error: 'ELF dependency inspection failed: ${snapshot.error}',
                onRetry: () => setState(() => dependencyTask = null),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final report = snapshot.data!;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dynamic dependencies',
                      style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('Source: ${report.source} · '
                         '${report.examinedEntries} entries examined'
                         '${report.truncated ? ' · partial' : ''}'),
                    if (report.soname != null)
                      SelectableText('SONAME: ${report.soname}'),
                    if (report.rpath != null)
                      SelectableText('RPATH: ${report.rpath}'),
                    if (report.runpath != null)
                      SelectableText('RUNPATH: ${report.runpath}'),
                    const SizedBox(height: 8),
                    Text('DT_NEEDED: ${report.needed.length} libraries'),
                    if (report.needed.isEmpty)
                      const Text('No dependency names decoded'),
                    for (final library in report.needed)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: SelectableText(library),
                      ),
                    if (report.warnings.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(report.warnings.join(' · ')),
                    ],
                    const SizedBox(height: 8),
                    const Text('Listed dependencies are declarations, '
                        'not proof that libraries are present or loadable.'),
                  ],
                ),
              ),
            );
          },
        ),
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
      if (symbolsTask != null)
        FutureBuilder<ElfSymbolReport>(
          future: symbolsTask,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorPanel(
                error: 'ELF symbol inspection failed: ${snapshot.error}',
                onRetry: () => setState(() => symbolsTask = null),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final data = snapshot.data!;
            final matches = data.symbols.where((item) {
              final matchesFilter = switch (symbolFilter) {
                'Imports' => item.imported,
                'Exports' => item.exported,
                'Other' => !item.imported && !item.exported,
                _ => true,
              };
              return matchesFilter &&
                  item.name.toLowerCase().contains(symbolQuery.toLowerCase());
            }).toList();

            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${data.symbols.length} named symbols shown · '
                  '${data.scanned} records inspected · '
                  '${data.imports} imports · ${data.exports} exports'
                  '${data.truncated ? ' · Partial results' : ''}'),
              if (data.warnings.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(data.warnings.join(' · ')),
                ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Filter symbol names',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => symbolQuery = value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('${widget.report.id}:$selectedFile:$symbolFilter'),
                initialValue: symbolFilter,
                decoration: const InputDecoration(
                  labelText: 'Symbol category',
                  border: OutlineInputBorder(),
                ),
                items: ['All', 'Imports', 'Exports', 'Other'].map((value) =>
                  DropdownMenuItem(value: value, child: Text(value))).toList(),
                onChanged: (value) => setState(() =>
                    symbolFilter = value ?? 'All'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 390,
                child: matches.isEmpty
                  ? const Center(child: Text('No matching symbols'))
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final sym = matches[index];
                        final label = sym.imported
                            ? 'Import' : sym.exported
                                ? 'Export' : 'Other';
                        return ListTile(
                          dense: true,
                          title: SelectableText(sym.name),
                          subtitle: Text(
                            '${sym.type} · ${sym.binding} · ${sym.visibility} · '
                            '${sym.dynamic ? '.dynsym' : '.symtab'}',
                          ),
                          trailing: Text(label),
                        );
                      },
                    ),
              ),
            ]);
          },
        ),
    ]);
  }
}



class _NativeGraphViewer extends StatefulWidget {
  const _NativeGraphViewer({super.key, required this.graph});
  final NativeDependencyGraph graph;

  @override
  State<_NativeGraphViewer> createState() => _NativeGraphViewerState();
}

class _NativeGraphViewerState extends State<_NativeGraphViewer> {
  String query = '';
  bool onlyLinked = false;

  @override
  Widget build(BuildContext context) {
    final graph = widget.graph;
    final lowercaseQuery = query.toLowerCase();
    final nodes = graph.nodes.where((node) {
      final outgoing = graph.edges
          .where((edge) => edge.fromPath == node.path).toList();
      final matches = node.path.toLowerCase().contains(lowercaseQuery) ||
          (node.soname?.toLowerCase().contains(lowercaseQuery) ?? false) ||
          outgoing.any((edge) =>
              edge.neededName.toLowerCase().contains(lowercaseQuery));
      return matches && (!onlyLinked || outgoing.isNotEmpty);
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Native dependency graph',
            style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('ABI folder: ${graph.abiDirectory}'),
          Text('${graph.nodes.length} packaged library nodes · '
              '${graph.edges.length} DT_NEEDED edges'
              '${graph.truncated ? ' · incomplete scan' : ''}'),
          const SizedBox(height: 6),
          const Text('Edges point from a library to its declared dependency. '
              'Not packaged means runtime availability is unknown.'),
          if (graph.cycles.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Possible dependency cycles: ${graph.cycles.join('; ')}'),
          ],
          if (graph.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(graph.warnings.join(' · '),
              maxLines: 5, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Filter libraries or dependency names',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => query = value),
          ),
          SwitchListTile(
            dense: true,
            title: const Text('Only libraries with outgoing dependencies'),
            value: onlyLinked,
            onChanged: (value) => setState(() => onlyLinked = value),
          ),
          SizedBox(
            height: 440,
            child: nodes.isEmpty
                ? const Center(child: Text('No matching graph nodes'))
                : ListView.builder(
                    itemCount: nodes.length,
                    itemBuilder: (context, index) {
                      final node = nodes[index];
                      final outgoing = graph.edges
                          .where((edge) => edge.fromPath == node.path).toList();
                      final root = node.path == graph.rootPath;
                      return Card(
                        child: ExpansionTile(
                          key: ValueKey(node.path),
                          initiallyExpanded: root,
                          leading: Icon(root
                              ? Icons.radio_button_checked
                              : Icons.memory),
                          title: Text(node.filename,
                            overflow: TextOverflow.ellipsis),
                          subtitle: Text(node.inspected
                              ? '${outgoing.length} declared dependencies'
                              : 'Packaged but not inspected'),
                          children: [
                            if (node.soname != null)
                              ListTile(
                                dense: true,
                                title: SelectableText('SONAME: ${node.soname}'),
                              ),
                            if (node.warning != null)
                              ListTile(
                                dense: true,
                                title: Text('Not inspected: ${node.warning}'),
                              ),
                            if (node.inspected && outgoing.isEmpty)
                              const ListTile(
                                dense: true,
                                title: Text('No DT_NEEDED entries decoded'),
                              ),
                            for (final edge in outgoing)
                              ListTile(
                                dense: true,
                                leading: Icon(
                                  edge.status == NativeDependencyStatus.packaged
                                      ? Icons.call_made
                                      : edge.status == NativeDependencyStatus.ambiguous
                                          ? Icons.help_outline
                                          : Icons.open_in_new,
                                ),
                                title: SelectableText(edge.neededName),
                                subtitle: Text(
                                  edge.status == NativeDependencyStatus.packaged
                                    ? 'Packaged: ${edge.toPath}'
                                    : edge.status == NativeDependencyStatus.ambiguous
                                      ? 'Ambiguous in APK: ${edge.candidates.join(', ')}'
                                      : 'Not packaged in this ABI · runtime unknown',
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
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
