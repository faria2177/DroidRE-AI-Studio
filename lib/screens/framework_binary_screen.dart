import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/apk_report.dart';
import '../services/framework_binary_inspector.dart';
import '../services/local_export_service.dart';

class FrameworkBinaryScreen extends StatefulWidget {
  const FrameworkBinaryScreen({super.key, required this.report});
  final ApkReport report;

  @override
  State<FrameworkBinaryScreen> createState() => _FrameworkBinaryScreenState();
}

class _FrameworkBinaryScreenState extends State<FrameworkBinaryScreen> {
  String? _entry;
  Map<String, Object?>? _result;
  bool _busy = false;
  String _message = '';

  Future<void> _inspect() async {
    setState(() {
      _busy = true;
      _result = null;
      _message = '';
    });
    try {
      final result = await FrameworkBinaryInspector.inspect(widget.report.localPath, _entry!);
      if (mounted) {
        setState(() => _result = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _save(String text) async {
    setState(() => _busy = true);
    try {
      final saved = await LocalExportService.saveFile(
        dialogTitle: 'Save framework evidence',
        fileName: 'framework-binary-evidence.json',
        bytes: Uint8List.fromList(utf8.encode(text)), protectedPath: widget.report.localPath,
      );
      if (mounted) {
        setState(() => _message = saved == null ? 'Export cancelled' : 'Report saved');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.report.entries.where((e) => e.isFile &&
        e.size <= FrameworkBinaryInspector.maxBytes &&
        FrameworkBinaryInspector.supports(e.name)).map((e) => e.name).toSet().toList()..sort();
    final entries = all.take(200).toList();
    final text = _result == null ? '' : const JsonEncoder.withIndent('  ').convert(_result);
    return Scaffold(
      appBar: AppBar(title: const Text('Framework Binary Inspector')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.report.fileName, style: Theme.of(context).textTheme.titleLarge),
        const Text('Offline Hermes headers, Unity metadata string evidence, '
            'React Native and NativeScript text previews. No bytecode execution or original source recovery.'),
        if (all.length > entries.length) const Text('First 200 eligible entries shown.'),
        if (entries.isEmpty) const Text('No supported members in the indexed archive list.'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _entry, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Framework member', border: OutlineInputBorder()),
          items: entries.map((path) => DropdownMenuItem(
            value: path, child: Text(path, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: _busy ? null : (value) => setState(() {
            _entry = value;
            _result = null;
            _message = '';
          }),
        ),
        FilledButton.icon(onPressed: _busy || _entry == null ? null : _inspect,
          icon: const Icon(Icons.search), label: const Text('Inspect selected member')),
        if (_busy) const LinearProgressIndicator(),
        if (_message.isNotEmpty) SelectableText(_message),
        if (_result != null) ...[
          Text('${_result!['kind']} · ${_result!['partial'] == true ? 'Partial evidence' : 'Text preview'}'),
          const Text('Review potentially sensitive strings before sharing.'),
          Wrap(spacing: 8, children: [
            OutlinedButton(onPressed: _busy ? null : () => _save(text), child: const Text('Export JSON')),
            OutlinedButton(onPressed: () => Clipboard.setData(ClipboardData(text: text)),
              child: const Text('Copy JSON')),
          ]),
          SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ],
      ]),
    );
  }
}
