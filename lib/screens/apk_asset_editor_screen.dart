import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/apk_report.dart';
import '../services/apk_asset_editor.dart';

class ApkAssetEditorScreen extends StatefulWidget {
  const ApkAssetEditorScreen({super.key, required this.report});
  final ApkReport report;

  @override
  State<ApkAssetEditorScreen> createState() => _ApkAssetEditorScreenState();
}

class _ApkAssetEditorScreenState extends State<ApkAssetEditorScreen> {
  final _text = TextEditingController();
  String? _selected;
  bool _loaded = false;
  bool _busy = false;
  String _status = '';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _loaded = false;
      _status = '';
    });
    try {
      final value = await ApkAssetEditor.load(widget.report, _selected!);
      if (mounted) {
        _text.text = value;
        setState(() => _loaded = true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'Load failed: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _export() async {
    if (_busy || !_loaded || _selected == null) {
      return;
    }
    final consent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create an unsigned APK copy?'),
        content: const Text('Only edit APKs you own or have permission to modify. '
            'The imported copy stays unchanged. All old signatures become '
            'invalid. Save under a new filename; align and sign with your own key.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm')),
        ],
      ),
    );
    if (!mounted || consent != true) {
      return;
    }
    setState(() {
      _busy = true;
      _status = '';
    });
    try {
      final result = await ApkAssetEditor.rebuild(widget.report, _selected!, _text.text);
      if (!mounted) {
        return;
      }
      final clean = widget.report.fileName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final base = clean.length > 48 ? clean.substring(0, 48) : clean;
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Save a NEW unsigned APK',
        fileName: '$base-edited-unsigned.apk',
        bytes: result.bytes,
      );
      if (mounted) {
        setState(() => _status = saved == null ? 'Export cancelled' :
          'Unsigned copy exported.\n'
          'Verified ${result.unchanged} unchanged file payloads.\n'
          'Removed ${result.removedSignatures} old JAR signature files.\n'
          'Before: ${result.beforeHash}\nAfter: ${result.afterHash}\n'
          'APK SHA-256: ${result.outputHash}\n'
          'Not signed, aligned or verified for installation.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'Export failed: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = widget.report.entries.where((e) =>
        e.isFile && e.size <= ApkAssetEditor.maxAsset &&
        ApkAssetEditor.editable(e.name)).map((e) => e.name).toSet().toList()..sort();
    final entries = candidates.take(200).toList();
    final supported = widget.report.fileName.toLowerCase().endsWith('.apk') &&
        widget.report.size <= ApkAssetEditor.maxInput;
    return Scaffold(
      appBar: AppBar(title: const Text('APK Asset Editor')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.report.fileName, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Edit one existing UTF-8 asset. Compiled resources, '
            'manifest and DEX are read-only. APK: 48 MiB / 64 MiB expanded.'),
        if (!supported) const Text('Unsupported archive type or size.'),
        if (entries.isEmpty) const Text('No eligible indexed assets.'),
        if (candidates.length > entries.length)
          const Text('Showing the first 200 eligible assets.'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _selected,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Existing asset', border: OutlineInputBorder()),
          items: entries.map((name) => DropdownMenuItem(
              value: name, child: Text(name, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: !supported || _busy ? null : (name) => setState(() {
            _selected = name;
            _loaded = false;
            _text.clear();
            _status = '';
          }),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: !supported || _busy || _selected == null ? null : _load,
          child: const Text('Load original asset'),
        ),
        if (_loaded) ...[
          TextField(controller: _text, enabled: !_busy, minLines: 8, maxLines: 16,
            autocorrect: false, enableSuggestions: false,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'UTF-8 content', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _busy ? null : _export,
            icon: const Icon(Icons.save_alt),
            label: const Text('Repack and export unsigned APK')),
        ],
        if (_busy) const LinearProgressIndicator(),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 10),
          SelectableText(_status),
        ],
      ]),
    );
  }
}
