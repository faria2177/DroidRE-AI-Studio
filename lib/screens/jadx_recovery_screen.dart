import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/apk_report.dart';
import '../services/jadx_source_recovery.dart';

class JadxRecoveryScreen extends StatefulWidget {
  const JadxRecoveryScreen({super.key, required this.report});
  final ApkReport report;

  @override
  State<JadxRecoveryScreen> createState() => _JadxRecoveryScreenState();
}

class _JadxRecoveryScreenState extends State<JadxRecoveryScreen> {
  String? _java, _jar, _folder;
  bool _trusted = false, _resources = true, _busy = false;
  String _status = '';
  JadxRecoveryResult? _result;

  Future<void> _pick(bool java) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: [java ? 'exe' : 'jar'],
    );
    final path = result?.files.single.path;
    if (mounted && path != null) {
      setState(() {
        if (java) {
          _java = path;
        } else {
          _jar = path;
        }
        _trusted = false;
      });
    }
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _result = null;
      _status = '';
    });
    try {
      final result = await JadxSourceRecovery.recover(report: widget.report,
        java: _java!, jar: _jar!, destination: _folder!, resources: _resources);
      if (mounted) {
        setState(() {
          _result = result;
          _status = result.log;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _java != null && _jar != null && _folder != null && _trusted;
    final result = _result;
    return PopScope(canPop: !_busy, child: Scaffold(
      appBar: AppBar(title: const Text('JADX Java Source Recovery')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.report.fileName, style: Theme.of(context).textTheme.titleLarge),
        const Text('Windows only. Use an official trusted JADX distribution and '
            'Java. No binary is uploaded. Decompiled files may be incomplete '
            'or incorrect and are not the original buildable source. '
            'The external parser is not sandboxed; analyze only authorized '
            'trusted input or use an isolated VM.'),
        OutlinedButton(onPressed: _busy ? null : () => _pick(true),
          child: Text(_java ?? 'Select java.exe')),
        OutlinedButton(onPressed: _busy ? null : () => _pick(false),
          child: Text(_jar ?? 'Select JADX distribution -all.jar')),
        OutlinedButton(onPressed: _busy ? null : () async {
          final path = await FilePicker.platform.getDirectoryPath();
          if (mounted && path != null) {
            setState(() => _folder = path);
          }
        }, child: Text(_folder ?? 'Choose output folder')),
        SwitchListTile(value: _resources, title: const Text('Decode resources too'),
          onChanged: _busy ? null : (v) => setState(() => _resources = v)),
        CheckboxListTile(value: _trusted,
          title: const Text('I trust these external tools and am authorized to analyze this APK'),
          onChanged: _busy ? null : (v) => setState(() => _trusted = v ?? false)),
        FilledButton.icon(onPressed: !ready || _busy ? null : _run,
          icon: const Icon(Icons.code), label: const Text('Decompile Java sources')),
        if (_busy) const LinearProgressIndicator(),
        if (result != null) ...[
          Text('${result.javaFiles} Java files · ${result.resourceFiles} resource files · '
              'exit ${result.exitCode}${result.partial ? ' · Partial output' : ''}'),
          SelectableText(result.folder),
          OutlinedButton.icon(onPressed: () async {
            try {
              await Process.start('explorer.exe', [result.folder], mode: ProcessStartMode.detached);
            } catch (error) {
              if (mounted) {
                setState(() => _status = '$error');
              }
            }
          }, icon: const Icon(Icons.folder_open), label: const Text('Open source output')),
        ],
        if (_status.isNotEmpty)
          SelectableText(_status, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ]),
    ));
  }
}
