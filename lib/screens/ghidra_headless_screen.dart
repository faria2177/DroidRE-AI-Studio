import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/ghidra_headless_service.dart';

class GhidraHeadlessScreen extends StatefulWidget {
  const GhidraHeadlessScreen({super.key, this.input, this.member});
  final String? input, member;
  @override
  State<GhidraHeadlessScreen> createState() => _GhidraHeadlessScreenState();
}

class _GhidraHeadlessScreenState extends State<GhidraHeadlessScreen> {
  String? _input, _java, _ghidra, _destination;
  bool _trusted = false, _busy = false;
  final _selector = TextEditingController();
  String _filter = '', _message = '';
  GhidraRun? _result;
  GhidraFunction? _current;

  @override
  void initState() {
    super.initState();
    _input = widget.input;
  }

  @override
  void dispose() {
    _selector.dispose();
    super.dispose();
  }

  Future<void> _pickFile(bool java) async {
    final selected = await FilePicker.platform.pickFiles();
    final path = selected?.files.single.path;
    if (mounted && path != null) {
      setState(() {
        if (java) {
          _java = path;
        } else {
          _input = path;
        }
        _trusted = false;
        _result = null;
        _current = null;
      });
    }
  }

  Future<void> _pickFolder(bool ghidra) async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (mounted && path != null) {
      setState(() {
        if (ghidra) {
          _ghidra = path;
          _trusted = false;
        } else {
          _destination = path;
        }
      });
    }
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _result = null;
      _current = null;
      _message = '';
    });
    try {
      final script = await rootBundle.loadString('assets/ghidra/DroidREHeadlessExport.java');
      final selection = _selector.text.trim();
      final result = await GhidraHeadlessService.run(java: _java!, ghidraRoot: _ghidra!,
        destination: _destination!, input: _input!, member: widget.member,
        script: script, selector: selection.isEmpty ? '@first' : selection);
      if (mounted) {
        setState(() {
          _result = result;
          _filter = '';
          _current = result.evidence.functions.isEmpty ? null : result.evidence.functions.first;
        });
      }
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

  void _navigate(String address) {
    final functions = _result!.evidence.functions.where((f) => f.address == address);
    if (functions.isEmpty) {
      setState(() => _message = 'Target is outside sampled function inventory');
      return;
    }
    setState(() => _current = functions.first);
  }

  @override
  Widget build(BuildContext context) {
    final ready = Platform.isWindows && !_busy && _trusted && _input != null &&
        _java != null && _ghidra != null && _destination != null;
    final result = _result;
    final current = _current;
    final functions = result?.evidence.functions.where((f) =>
      '${f.name} ${f.address}'.toLowerCase().contains(_filter.toLowerCase())).toList() ??
      <GhidraFunction>[];
    final callers = current == null || result == null ? <GhidraFunction>[] :
      result.evidence.functions.where((f) => f.calls.any((c) => c.address == current.address)).toList();
    return PopScope(canPop: !_busy, child: Scaffold(
      appBar: AppBar(title: const Text('Ghidra Native Decompiler')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Windows · trusted external Ghidra and compatible JDK required. '
          'Analyzes a fresh copy. External parsers are not sandboxed. '
          'Use authorized files and trusted tools or an isolated VM.'),
        if (widget.member == null)
          OutlinedButton(onPressed: _busy ? null : () => _pickFile(false),
            child: Text(_input ?? 'Select ELF / SO / EXE / DLL')),
        if (widget.member != null) SelectableText('APK member: ${widget.member}'),
        OutlinedButton(onPressed: _busy ? null : () => _pickFile(true),
          child: Text(_java ?? 'Select JDK java.exe')),
        OutlinedButton(onPressed: _busy ? null : () => _pickFolder(true),
          child: Text(_ghidra ?? 'Select Ghidra installation folder')),
        OutlinedButton(onPressed: _busy ? null : () => _pickFolder(false),
          child: Text(_destination ?? 'Select analysis session parent')),
        TextField(controller: _selector, enabled: !_busy, maxLength: 128,
          decoration: const InputDecoration(labelText: 'Exact function address/name (optional)',
            helperText: 'Blank: decompile first 12 sampled functions')),
        CheckboxListTile(value: _trusted,
          title: const Text('I trust the tools and authorize analysis of this binary'),
          onChanged: _busy ? null : (v) => setState(() => _trusted = v ?? false)),
        FilledButton(onPressed: ready ? _run : null, child: const Text('Run Ghidra static analysis')),
        if (_busy) const LinearProgressIndicator(),
        if (_message.isNotEmpty) SelectableText(_message),
        if (result != null) ...[
          Text('${result.evidence.language} · ${result.evidence.functions.length} functions · partial evidence'),
          SelectableText('SHA-256: ${result.hash}\nSession: ${result.folder}'),
          const Text('Observed static calls only; not a complete runtime call graph.'),
          TextField(onChanged: (v) => setState(() => _filter = v),
            decoration: const InputDecoration(labelText: 'Filter functions')),
          SizedBox(height: 190, child: ListView.builder(itemCount: functions.length,
            itemBuilder: (context, i) => ListTile(
              dense: true, selected: current?.address == functions[i].address,
              title: Text(functions[i].name), subtitle: Text(functions[i].address),
              onTap: () => setState(() => _current = functions[i])))),
          if (current != null) ...[
            Text('${current.name} @ ${current.address}', style: Theme.of(context).textTheme.titleLarge),
            ExpansionTile(title: Text('Incoming observed calls (${callers.length})'),
              children: callers.map((caller) => ListTile(title: Text(caller.name),
                subtitle: Text(caller.address), onTap: () => _navigate(caller.address))).toList()),
            ExpansionTile(title: Text('Outgoing observed calls (${current.calls.length})'),
              children: current.calls.map((call) => ListTile(title: Text(call.name),
                subtitle: Text(call.address), onTap: () => _navigate(call.address))).toList()),
            const Text('C-like decompiler output — not original C/C++ source.'),
            if (current.pseudocode == null)
              OutlinedButton(onPressed: () => setState(() {
                _selector.text = current.address;
                _message = 'Run analysis again for this exact function.';
              }), child: const Text('Select function for next run'))
            else ...[
              Text(current.status ?? 'Unknown status'),
              OutlinedButton(onPressed: () => Clipboard.setData(ClipboardData(text: current.pseudocode!)),
                child: const Text('Copy pseudocode')),
              SelectableText(current.pseudocode!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ],
          ],
          ExpansionTile(title: const Text('Tool log'), children: [SelectableText(result.log)]),
        ],
      ]),
    ));
  }
}
