import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/local_export_service.dart';
import '../services/universal_binary_inspector.dart';

class UniversalBinaryScreen extends StatefulWidget {
  const UniversalBinaryScreen({super.key});

  @override
  State<UniversalBinaryScreen> createState() => _UniversalBinaryScreenState();
}

class _UniversalBinaryScreenState extends State<UniversalBinaryScreen> {
  String? _path;
  Uint8List? _bytes;
  Map<String, Object?>? _info;
  final _offset = TextEditingController(text: '0');
  final _pattern = TextEditingController();
  final _patch = TextEditingController();
  int _at = 0;
  bool _hex = true, _busy = false;
  String _message = '';
  List<int> _hits = [];

  @override
  void dispose() {
    _offset.dispose();
    _pattern.dispose();
    _patch.dispose();
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

  Future<void> _open() async {
    final result = await FilePicker.platform.pickFiles();
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }
    final bytes = await UniversalBinaryInspector.load(path);
    final info = await Isolate.run(() => UniversalBinaryInspector.inspect(bytes));
    if (mounted) {
      setState(() {
        _path = path;
        _bytes = bytes;
        _info = info;
        _at = 0;
        _offset.text = '0';
        _hits = [];
        _patch.clear();
      });
    }
  }

  int _parseOffset() {
    final raw = _offset.text.trim().toLowerCase();
    final value = int.tryParse(raw.startsWith('0x') ? raw.substring(2) : raw, radix: 16);
    if (value == null || value < 0 || value >= _bytes!.length) {
      throw const FormatException('Enter a valid hexadecimal file offset');
    }
    return value;
  }

  void _jump(int at) {
    setState(() {
      _at = at;
      _offset.text = at.toRadixString(16);
    });
  }

  Future<void> _search() async {
    final bytes = _bytes!;
    final pattern = UniversalBinaryInspector.pattern(_pattern.text, hex: _hex);
    final result = await Isolate.run(() => UniversalBinaryInspector.search(bytes, pattern));
    if (mounted) {
      setState(() {
        _hits = result.$1;
        _message = '${_hits.length} matches${result.$2 ? ' (limited)' : ''}';
      });
    }
  }

  Future<void> _savePatch() async {
    final offset = _parseOffset();
    final patch = UniversalBinaryInspector.pattern(_patch.text);
    final original = _bytes!;
    final copy = UniversalBinaryInspector.patchedCopy(original, offset, patch);
    final consent = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Export modified binary copy?'),
      content: Text('Replace ${patch.length} bytes at 0x${offset.toRadixString(16)}. '
          'Only modify files you own or are authorized to edit. '
          'This may invalidate signatures, checksums and executable structure. '
          'The output is not verified runnable. Choose a new filename.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Export copy')),
      ],
    ));
    if (consent != true || !mounted) {
      return;
    }
    final saved = await LocalExportService.saveFile(dialogTitle: 'Save modified copy',
      fileName: 'modified-copy.bin', bytes: copy, protectedPath: _path);
    if (mounted) {
      setState(() => _message = saved == null ? 'Export cancelled' : 'Copy saved; loaded original unchanged');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Scaffold(
      appBar: AppBar(title: const Text('Universal Binary Inspector')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Local binary files up to 32 MiB. Header evidence, hex pages and exact byte search. Files are never executed.'),
        FilledButton.icon(onPressed: _busy ? null : () => _task(_open),
          icon: const Icon(Icons.file_open), label: const Text('Open binary file')),
        if (_busy) const LinearProgressIndicator(),
        if (bytes != null) ...[
          ExpansionTile(title: Text('${_info!['kind']} · ${bytes.length} bytes'),
            children: [SelectableText(const JsonEncoder.withIndent('  ').convert(_info),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12))]),
          TextField(controller: _offset, enabled: !_busy,
            decoration: const InputDecoration(labelText: 'File offset (hex)')),
          Wrap(spacing: 8, children: [
            OutlinedButton(onPressed: _busy ? null : () => _task(() async => _jump(_parseOffset())),
              child: const Text('Go')),
            OutlinedButton(onPressed: _busy || _at == 0 ? null :
              () => _jump((_at - UniversalBinaryInspector.pageSize).clamp(0, _at).toInt()),
              child: const Text('Previous')),
            OutlinedButton(onPressed: _busy || _at + UniversalBinaryInspector.pageSize >= bytes.length
              ? null : () => _jump(_at + UniversalBinaryInspector.pageSize),
              child: const Text('Next')),
          ]),
          SingleChildScrollView(scrollDirection: Axis.horizontal,
            child: SelectableText(UniversalBinaryInspector.hexPage(bytes, _at),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
          SwitchListTile(value: _hex, title: const Text('Hex search (off = UTF-8 text)'),
            onChanged: _busy ? null : (value) => setState(() => _hex = value)),
          TextField(controller: _pattern, enabled: !_busy, maxLength: 768,
            decoration: const InputDecoration(labelText: 'Exact search pattern')),
          OutlinedButton(onPressed: _busy ? null : () => _task(_search),
            child: const Text('Search bytes')),
          if (_hits.isNotEmpty)
            SizedBox(height: 160, child: ListView.builder(
              itemCount: _hits.length,
              itemBuilder: (context, i) => ListTile(dense: true,
                title: Text('0x${_hits[i].toRadixString(16)}'),
                onTap: _busy ? null : () => _jump(_hits[i])))),
          if (Platform.isWindows) ...[
            const Divider(),
            const Text('Copy-only hex replacement (same file length; offset above).'),
            TextField(controller: _patch, enabled: !_busy, maxLength: 768,
              decoration: const InputDecoration(labelText: 'Replacement hex bytes')),
            OutlinedButton(onPressed: _busy ? null : () => _task(_savePatch),
              child: const Text('Export modified binary copy')),
          ],
        ],
        if (_message.isNotEmpty) SelectableText(_message),
      ]),
    );
  }
}
