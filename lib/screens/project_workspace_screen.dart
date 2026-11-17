import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../services/local_export_service.dart';
import '../services/project_workspace_service.dart';
import '../services/project_context_search.dart';
import '../services/saf_source_recovery_service.dart';

/// Lightweight lexical coloring, not a language parser.
class WorkspaceCodeController extends TextEditingController {
  WorkspaceCodeController({required super.text});
  static final tokens = RegExp(
    r'//[^\r\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|'
    r"\x27(?:\\.|[^\x27\\])*\x27|"
    r'\b(?:class|interface|enum|public|private|protected|static|void|int|bool|'
    r'final|const|var|return|if|else|for|while|new|import|package|using|'
    r'namespace|fun|val|async|await|try|catch|throw|extends|implements|null|'
    r'true|false|function|let|def|virtual|override|struct)\b|\b(?:0x[0-9a-fA-F]+|\d+)\b',
  );

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style,
      required bool withComposing}) {
    if (text.length > ProjectWorkspaceService.maxTextBytes ||
        (withComposing && value.composing.isValid && !value.composing.isCollapsed)) {
      return super.buildTextSpan(context: context, style: style,
          withComposing: withComposing);
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final spans = <TextSpan>[];
    var at = 0;
    for (final match in tokens.allMatches(text)) {
      if (match.start > at) {
        spans.add(TextSpan(text: text.substring(at, match.start)));
      }
      final word = match.group(0)!;
      final color = word.startsWith('//') || word.startsWith('/*')
          ? (dark ? const Color(0xff91b49a) : const Color(0xff367248))
          : word.startsWith('"') || word.startsWith("'")
              ? (dark ? const Color(0xfff0ba85) : const Color(0xffa34616))
              : (dark ? const Color(0xff9ec5ff) : const Color(0xff244daf));
      spans.add(TextSpan(text: word, style: TextStyle(color: color)));
      at = match.end;
    }
    if (at < text.length) {
      spans.add(TextSpan(text: text.substring(at)));
    }
    return TextSpan(style: style, children: spans);
  }
}

class _WorkspaceTab {
  _WorkspaceTab(this.path, this.original)
      : controller = WorkspaceCodeController(text: original);
  final String path, original;
  final WorkspaceCodeController controller;
  bool get dirty => controller.text != original;
}

class _TreeNode {
  _TreeNode(this.name, this.path, this.file);
  final String name, path;
  final bool file;
  final Map<String, _TreeNode> children = {};
}

class ProjectWorkspaceScreen extends StatefulWidget {
  const ProjectWorkspaceScreen({super.key, this.folderPath, this.folderUri});
  final String? folderPath, folderUri;

  @override
  State<ProjectWorkspaceScreen> createState() => _ProjectWorkspaceScreenState();
}

class _ProjectWorkspaceScreenState extends State<ProjectWorkspaceScreen> {
  String? _root, _uri;
  List<String> _paths = [];
  final _tabs = <_WorkspaceTab>[];
  int _active = -1;
  bool _busy = false, _partial = false, _exitConfirmed = false, _askingExit = false;
  String _message = '', _filter = '';
  final _find = TextEditingController();
  final _global = TextEditingController();

  bool get _editable => Platform.isWindows && _uri == null;
  _WorkspaceTab? get _current => _active >= 0 ? _tabs[_active] : null;

  @override
  void initState() {
    super.initState();
    _root = widget.folderPath;
    _uri = widget.folderUri;
    if (_root != null || _uri != null) {
      _task(_reload);
    }
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.controller.dispose();
    }
    _find.dispose();
    _global.dispose();
    super.dispose();
  }

  Future<void> _task(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _message = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_tabs.any((tab) => tab.dirty)) {
      return true;
    }
    return await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Discard edited drafts?'),
      content: const Text('Changes are in memory. Export edited copies first if needed.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
      ],
    )) == true;
  }

  Future<void> _choose() async {
    if (!await _confirmDiscard() || !mounted) {
      return;
    }
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose recovered source workspace');
    if (path == null || !mounted) {
      return;
    }
    final canonical = await Directory(path).resolveSymbolicLinks();
    final listing = await ProjectWorkspaceService.list(canonical);
    if (mounted) {
      setState(() {
        for (final tab in _tabs) {
          tab.controller.dispose();
        }
        _tabs.clear();
        _active = -1;
        _root = canonical;
        _uri = null;
        _paths = listing.paths;
        _partial = listing.partial;
        _filter = '';
      });
    }
  }

  Future<void> _reload() async {
    final WorkspaceListing listing;
    if (_uri != null) {
      final paths = await SafSourceRecoveryService.listFiles(_uri!);
      listing = WorkspaceListing(
        paths.where(ProjectWorkspaceService.eligible)
            .toSet().take(ProjectWorkspaceService.maxFiles).toList()..sort(), true);
    } else {
      listing = await ProjectWorkspaceService.list(_root!);
    }
    if (mounted) {
      setState(() {
        _paths = listing.paths;
        _partial = listing.partial;
      });
    }
  }

  Future<void> _open(String path, {int? line}) async {
    final existing = _tabs.indexWhere((tab) => tab.path == path);
    if (existing >= 0) {
      setState(() => _active = existing);
    } else {
      if (_tabs.length >= ProjectWorkspaceService.maxTabs) {
        throw const FormatException('Close a tab first (maximum 8)');
      }
      final text = _uri != null
          ? await SafSourceRecoveryService.readFile(_uri!, path)
          : await ProjectWorkspaceService.read(_root!, path);
      if (_uri != null && text.startsWith('This file is larger')) {
        throw const FormatException('File exceeds the SAF preview limit');
      }
      ProjectWorkspaceService.exportBytes(text);
      if (!mounted) {
        return;
      }
      setState(() {
        _tabs.add(_WorkspaceTab(path, text));
        _active = _tabs.length - 1;
      });
    }
    if (line != null) {
      final controller = _current!.controller;
      var at = 0;
      for (var i = 1; i < line; i++) {
        final next = controller.text.indexOf('\n', at);
        if (next < 0) {
          break;
        }
        at = next + 1;
      }
      controller.selection = TextSelection.collapsed(offset: at);
    }
  }

  Future<void> _closeTab(int index) async {
    final tab = _tabs[index];
    if (tab.dirty) {
      final discard = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Close edited draft?'),
        content: Text(tab.path),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard draft')),
        ],
      ));
      if (discard != true || !mounted) {
        return;
      }
    }
    setState(() {
      _tabs.removeAt(index).controller.dispose();
      if (_tabs.isEmpty) {
        _active = -1;
      } else if (_active > index) {
        _active--;
      } else if (_active == index) {
        _active = index.clamp(0, _tabs.length - 1).toInt();
      }
    });
  }

  Future<void> _export() async {
    final tab = _current!;
    final bytes = Uint8List.fromList(ProjectWorkspaceService.exportBytes(tab.controller.text));
    final selected = await FilePicker.platform.saveFile(
        dialogTitle: 'Export draft as a NEW file outside source workspace',
        fileName: 'edited-${p.basename(tab.path)}');
    if (selected == null || !mounted) {
      return;
    }
    final target = File(selected);
    final base = await Directory(_root!).resolveSymbolicLinks();
    final parent = await target.parent.resolveSymbolicLinks();
    final candidate = p.join(parent, p.basename(selected));
    if (p.isWithin(base, candidate) || p.equals(base, candidate)) {
      throw const FormatException('Choose an output outside the input workspace');
    }
    if (await FileSystemEntity.type(candidate, followLinks: false) != FileSystemEntityType.notFound) {
      throw const FormatException('Choose a new output filename');
    }
    // Reuse desktop no-overwrite path guard.
    await LocalExportService.writeDesktopFile(candidate, bytes,
        protectedPath: p.joinAll([base, ...tab.path.split('/')]));
    if (mounted) {
      setState(() => _message = 'Exported a copy; source files unchanged');
    }
  }

  void _findNext() {
    final tab = _current;
    final needle = _find.text;
    if (tab == null || needle.isEmpty) {
      return;
    }
    final controller = tab.controller;
    final start = controller.selection.end.clamp(0, controller.text.length).toInt();
    var hit = controller.text.indexOf(needle, start);
    if (hit < 0) {
      hit = controller.text.indexOf(needle);
    }
    if (hit < 0) {
      setState(() => _message = 'No exact match in this draft');
      return;
    }
    controller.selection = TextSelection(baseOffset: hit, extentOffset: hit + needle.length);
    setState(() => _message = 'Match at character ${hit + 1}');
  }

  Future<void> _globalSearch() async {
    final query = _global.text;
    final result = _uri != null
        ? await ProjectContextSearch.saf(_uri!, query)
        : await ProjectContextSearch.local(_root!, query);
    if (!mounted) {
      return;
    }
    final selected = await showDialog<CodeEvidence>(context: context,
      builder: (context) => AlertDialog(
        title: Text('${result.matches.length} results${result.partial ? ' · Partial' : ''}'),
        content: SizedBox(width: 600, height: 420, child: ListView.builder(
          itemCount: result.matches.length,
          itemBuilder: (context, i) {
            final hit = result.matches[i];
            return ListTile(title: Text('${hit.path}:${hit.firstLine}'),
              subtitle: Text(hit.text, maxLines: 5, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(context, hit));
          })),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ));
    if (selected != null && mounted) {
      await _open(selected.path, line: selected.firstLine);
    }
  }

  List<Widget> _tree() {
    final root = _TreeNode('', '', false);
    for (final path in _paths.where((s) => s.toLowerCase().contains(_filter.toLowerCase()))) {
      final parts = path.split('/');
      var node = root;
      for (var i = 0; i < parts.length; i++) {
        final name = parts[i];
        final parent = node;
        node = parent.children.putIfAbsent(name, () =>
          _TreeNode(name, parts.take(i + 1).join('/'), i == parts.length - 1));
      }
    }
    List<Widget> children(_TreeNode parent) {
      final entries = parent.children.values.toList()
          ..sort((a, b) => a.file != b.file ? (a.file ? 1 : -1) : a.name.compareTo(b.name));
      return [
        for (final node in entries)
          if (node.file)
            ListTile(dense: true, leading: const Icon(Icons.code, size: 17),
              title: Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              selected: _current?.path == node.path,
              onTap: _busy ? null : () => _task(() => _open(node.path)))
          else
            ExpansionTile(key: PageStorageKey(node.path), dense: true,
              initiallyExpanded: _filter.isNotEmpty, leading: const Icon(Icons.folder_outlined),
              title: Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              childrenPadding: const EdgeInsets.only(left: 10), children: children(node)),
      ];
    }
    return children(root);
  }

  Widget _sidebar() => Column(children: [
    Padding(padding: const EdgeInsets.all(8), child: TextField(
      onChanged: (v) => setState(() => _filter = v),
      decoration: const InputDecoration(labelText: 'Filter file tree', prefixIcon: Icon(Icons.search)))),
    Padding(padding: const EdgeInsets.all(8), child: TextField(
      controller: _global, enabled: !_busy,
      decoration: const InputDecoration(labelText: 'Search disk code'),
      onSubmitted: (_) => _task(_globalSearch))),
    OutlinedButton(onPressed: _busy ? null : () => _task(_globalSearch),
      child: const Text('Global search')),
    Text('${_paths.length} text paths${_partial ? ' · Partial' : ''}'),
    Expanded(child: ListView(children: _tree())),
  ]);

  Widget _editor() {
    final tab = _current;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (var i = 0; i < _tabs.length; i++)
          Padding(padding: const EdgeInsets.all(3), child: InputChip(
            label: Text('${p.basename(_tabs[i].path)}${_tabs[i].dirty ? ' *' : ''}'),
            selected: _active == i,
            onPressed: _busy ? null : () => setState(() => _active = i),
            onDeleted: _busy ? null : () => _closeTab(i))),
      ])),
      if (tab == null)
        const Expanded(child: Center(child: Text('Select a text file from the tree')))
      else ...[
        Padding(padding: const EdgeInsets.all(8), child: Text(tab.path,
          maxLines: 2, overflow: TextOverflow.ellipsis)),
        Row(children: [
          Expanded(child: TextField(controller: _find, enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Find in tab'),
            onSubmitted: (_) => _findNext())),
          IconButton(onPressed: _busy ? null : _findNext, tooltip: 'Find next',
            icon: const Icon(Icons.search)),
          if (_editable)
            IconButton(onPressed: _busy ? null : () => _task(_export),
              tooltip: 'Export edited copy', icon: const Icon(Icons.save_alt)),
        ]),
        Expanded(child: TextField(key: ValueKey(tab.path), controller: tab.controller,
          onChanged: (_) => setState(() {}),
          readOnly: !_editable || _busy, expands: true, minLines: null, maxLines: null,
          autocorrect: false, enableSuggestions: false,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(12)))),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final hasRoot = _root != null || _uri != null;
    return PopScope(canPop: _exitConfirmed || (!_busy && !_tabs.any((t) => t.dirty)),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _busy || _askingExit || _exitConfirmed) {
          return;
        }
        _askingExit = true;
        final discard = await _confirmDiscard();
        _askingExit = false;
        if (discard && mounted) {
          setState(() => _exitConfirmed = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).pop();
            }
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Universal Project Workspace'), actions: [
          if (Platform.isWindows)
            IconButton(onPressed: _busy ? null : () => _task(_choose),
              icon: const Icon(Icons.folder_open), tooltip: 'Open source folder'),
          if (hasRoot)
            IconButton(onPressed: _busy ? null : () => _task(_reload),
              icon: const Icon(Icons.refresh), tooltip: 'Refresh files'),
        ]),
        body: Column(children: [
          Padding(padding: const EdgeInsets.all(8), child: Text(
            _editable ? 'Local drafts · export copies outside the source tree · search reads disk'
                : 'Read-only local preview · search reads disk/provider, not unsaved drafts')),
          if (_busy) const LinearProgressIndicator(),
          if (_message.isNotEmpty)
            Padding(padding: const EdgeInsets.all(8), child: Text(_message)),
          Expanded(child: !hasRoot
            ? Center(child: FilledButton(onPressed: Platform.isWindows && !_busy
                ? () => _task(_choose) : null, child: const Text('Open recovered source folder')))
            : LayoutBuilder(builder: (context, constraints) {
                if (constraints.maxWidth >= 760) {
                  return Row(children: [
                    SizedBox(width: 275, child: _sidebar()),
                    const VerticalDivider(width: 1),
                    Expanded(child: _editor()),
                  ]);
                }
                return Column(children: [
                  Flexible(flex: 2, child: _sidebar()),
                  const Divider(height: 1),
                  Expanded(flex: 3, child: _editor()),
                ]);
              })),
        ]),
      ));
  }
}
