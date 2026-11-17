import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/apk_report.dart';
import '../services/apktool_workspace.dart';

class ApktoolWorkspaceScreen extends StatefulWidget {
  const ApktoolWorkspaceScreen({super.key, required this.report});
  final ApkReport report;

  @override
  State<ApktoolWorkspaceScreen> createState() => _ApktoolWorkspaceScreenState();
}

class _ApktoolWorkspaceScreenState extends State<ApktoolWorkspaceScreen> {
  final _text = TextEditingController();
  String? _java, _jar, _parent, _root, _file, _output;
  bool _consent = false;
  bool _busy = false;
  bool _dirty = false;
  String _log = '';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _task(Future<void> Function() task) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _log = '';
    });
    try {
      await task();
    } catch (error) {
      if (mounted) {
        setState(() => _log = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  ApktoolWorkspace get _engine => ApktoolWorkspace(javaPath: _java!, jarPath: _jar!);

  Future<String?> _pickFile(String extension, {String? directory}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: [extension],
      initialDirectory: directory,
    );
    return result?.files.single.path;
  }

  Future<void> _openText() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['smali', 'xml'],
      initialDirectory: _root,
    );
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }
    final text = await ApktoolWorkspace.readText(_root!, path);
    if (mounted) {
      _text.text = text;
      setState(() {
        _file = path;
        _dirty = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _java != null && _jar != null && _parent != null && _consent;
    return Scaffold(
      appBar: AppBar(title: const Text('Smali & Resource Workspace')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.report.fileName, style: Theme.of(context).textTheme.titleLarge),
        const Text('Windows only. Requires separately installed Java and a trusted '
            'official Apktool JAR. No APK code is launched. Use only authorized '
            'packages. Rebuilt output is unsigned; no installability guarantee.'),
        CheckboxListTile(value: _consent,
          title: const Text('I authorize local decoding and trust my selected Java/Apktool executable'),
          onChanged: _busy ? null : (value) => setState(() => _consent = value ?? false)),
        OutlinedButton(onPressed: _busy || _root != null ? null : () => _task(() async {
          final path = await _pickFile('exe');
          if (mounted && path != null) {
            setState(() => _java = path);
          }
        }), child: Text(_java ?? 'Select java.exe')),
        OutlinedButton(onPressed: _busy || _root != null ? null : () => _task(() async {
          final path = await _pickFile('jar');
          if (mounted && path != null) {
            setState(() => _jar = path);
          }
        }), child: Text(_jar ?? 'Select trusted Apktool JAR')),
        OutlinedButton(onPressed: _busy || _root != null ? null : () => _task(() async {
          final path = await FilePicker.platform.getDirectoryPath();
          if (mounted && path != null) {
            setState(() => _parent = path);
          }
        }), child: Text(_parent ?? 'Choose output parent folder')),
        FilledButton.icon(onPressed: !ready || _busy || _root != null ? null : () =>
          _task(() async {
            final result = await _engine.decode(widget.report, _parent!);
            if (mounted) {
              setState(() {
                _root = result.$1;
                _log = result.$2;
              });
            }
          }), icon: const Icon(Icons.folder_open), label: const Text('Decode APK into workspace')),
        if (_root != null) ...[
          SelectableText(_root!),
          OutlinedButton.icon(onPressed: _busy ? null : () => _task(() async {
            await Process.start('explorer.exe', [_root!], mode: ProcessStartMode.detached);
          }), icon: const Icon(Icons.folder), label: const Text('Open decoded folder')),
          OutlinedButton(onPressed: _busy || _dirty ? null : () => _task(_openText),
            child: const Text('Open Smali / XML file')),
          if (_file != null) ...[
            SelectableText(_file!),
            TextField(controller: _text, enabled: !_busy, minLines: 12, maxLines: 28,
              onChanged: (_) => setState(() => _dirty = true),
              autocorrect: false, enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Workspace source')),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: _busy || !_dirty ? null : () => _task(() async {
                await ApktoolWorkspace.saveText(_root!, _file!, _text.text);
                if (mounted) {
                  setState(() {
                    _dirty = false;
                    _log = 'Workspace file saved; original APK unchanged.';
                  });
                }
              }), child: const Text('Save edit'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: _busy || !_dirty ? null : () => _task(() async {
                final value = await ApktoolWorkspace.readText(_root!, _file!);
                if (mounted) {
                  _text.text = value;
                  setState(() => _dirty = false);
                }
              }), child: const Text('Discard unsaved edit'))),
            ]),
          ],
          FilledButton.icon(onPressed: !ready || _busy || _dirty ? null : () => _task(() async {
            final result = await _engine.build(_root!);
            if (mounted) {
              setState(() {
                _output = result.$1;
                _log = result.$2;
              });
            }
          }), icon: const Icon(Icons.build), label: const Text('Rebuild unsigned APK')),
          if (_output != null) SelectableText('Unsigned output: $_output'),
        ],
        if (_busy) const LinearProgressIndicator(),
        if (_log.isNotEmpty) SelectableText(_log, style: const TextStyle(fontFamily: 'monospace')),
      ]),
    );
  }
}
