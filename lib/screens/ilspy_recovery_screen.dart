import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ilspy_recovery.dart';

class IlspyRecoveryScreen extends StatefulWidget {
  const IlspyRecoveryScreen({super.key, required this.input, required this.hash});
  final String input, hash;

  @override
  State<IlspyRecoveryScreen> createState() => _IlspyRecoveryScreenState();
}

class _IlspyRecoveryScreenState extends State<IlspyRecoveryScreen> {
  String? _exe, _destination;
  bool _trusted = false, _busy = false;
  IlspyMode _mode = IlspyMode.il;
  IlspyResult? _result;
  String _error = '';

  Future<void> _choose() async {
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['exe']);
    final path = selected?.files.single.path;
    if (mounted && path != null) {
      setState(() {
        _exe = path;
        _trusted = false;
      });
    }
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _result = null;
      _error = '';
    });
    try {
      final result = await IlspyRecovery.run(executable: _exe!, input: widget.input,
        expectedHash: widget.hash, mode: _mode, destination: _destination);
      if (mounted) {
        setState(() => _result = result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final ready = !_busy && _trusted && _exe != null &&
        (_mode != IlspyMode.project || _destination != null);
    return PopScope(canPop: !_busy, child: Scaffold(
      appBar: AppBar(title: const Text('.NET IL & C# Recovery')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Windows · requires trusted installed ILSpy CLI. The external '
            'parser is not sandboxed; use authorized trusted input or an isolated VM. '
            'No build or execution of recovered code. Decompiled output is not original source.'),
        SelectableText(widget.input),
        OutlinedButton(onPressed: _busy ? null : _choose,
          child: Text(_exe ?? 'Select ilspycmd.exe')),
        CheckboxListTile(value: _trusted,
          title: const Text('I trust the selected tool and authorize analysis of this assembly'),
          onChanged: _busy ? null : (v) => setState(() => _trusted = v ?? false)),
        DropdownButtonFormField<IlspyMode>(initialValue: _mode,
          decoration: const InputDecoration(labelText: 'Analysis mode'),
          items: const [
            DropdownMenuItem(value: IlspyMode.il, child: Text('IL instruction preview')),
            DropdownMenuItem(value: IlspyMode.csharp, child: Text('C# decompiled preview')),
            DropdownMenuItem(value: IlspyMode.types, child: Text('List managed types')),
            DropdownMenuItem(value: IlspyMode.project, child: Text('Export C# project')),
          ],
          onChanged: _busy ? null : (v) => setState(() {
            _mode = v ?? IlspyMode.il;
            _result = null;
          })),
        if (_mode == IlspyMode.project)
          OutlinedButton(onPressed: _busy ? null : () async {
            final selected = await FilePicker.platform.getDirectoryPath();
            if (mounted && selected != null) {
              setState(() => _destination = selected);
            }
          }, child: Text(_destination ?? 'Choose output parent folder')),
        FilledButton(onPressed: ready ? _run : null, child: const Text('Run ILSpy analysis')),
        if (_busy) const LinearProgressIndicator(),
        if (_error.isNotEmpty) SelectableText(_error),
        if (result != null) ...[
          Text('Exit ${result.exitCode} · ${result.partial ? 'Partial output' : 'Tool completed'}'),
          if (result.folder != null) ...[
            SelectableText(result.folder!),
            OutlinedButton(onPressed: () async {
              try {
                await Process.start('explorer.exe', [result.folder!], mode: ProcessStartMode.detached);
              } catch (e) {
                if (mounted) {
                  setState(() => _error = '$e');
                }
              }
            }, child: const Text('Open project folder')),
          ],
          OutlinedButton(onPressed: () => Clipboard.setData(ClipboardData(text: result.output)),
            child: const Text('Copy visible output')),
          SelectableText(result.output, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ],
      ]),
    ));
  }
}
