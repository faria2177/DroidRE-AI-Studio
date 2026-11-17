import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/paged_binary_service.dart';
import '../services/universal_binary_inspector.dart';

class PagedBinaryScreen extends StatefulWidget {
  const PagedBinaryScreen({super.key});
  @override
  State<PagedBinaryScreen> createState() => _PagedBinaryScreenState();
}

class _PagedBinaryScreenState extends State<PagedBinaryScreen> {
  PagedBinaryFile? _file;
  final _offset = TextEditingController(text: '0');
  final _pattern = TextEditingController();
  String _page = '', _status = '';
  int _at = 0;
  int? _next;
  List<int> _hits = [];
  bool _busy = false;

  @override
  void dispose() {
    _offset.dispose();
    _pattern.dispose();
    super.dispose();
  }

  Future<void> _task(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _status = '';
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _status = '$e');
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
    final file = await PagedBinaryService.open(path);
    final bytes = await PagedBinaryService.page(file, 0);
    if (!mounted) {
      return;
    }
    setState(() {
      _file = file;
      _at = 0;
      _offset.text = '0';
      _page = UniversalBinaryInspector.hexPage(bytes, 0);
      _hits = [];
      _next = null;
    });
  }

  int _parse() {
    final value = _offset.text.trim().toLowerCase();
    final at = int.tryParse(value.startsWith('0x') ? value.substring(2) : value, radix: 16);
    if (at == null || at < 0 || at >= _file!.length) {
      throw const FormatException('Invalid hexadecimal offset');
    }
    return at;
  }

  Future<void> _show(int at) async {
    final bytes = await PagedBinaryService.page(_file!, at);
    if (mounted) {
      setState(() {
        _at = at;
        _offset.text = at.toRadixString(16);
        _page = UniversalBinaryInspector.hexPage(bytes, 0);
      });
    }
  }

  Future<void> _search(int start) async {
    final result = await PagedBinaryService.search(_file!, start,
      UniversalBinaryInspector.pattern(_pattern.text));
    if (mounted) {
      setState(() {
        _hits = result.$1;
        _next = result.$2;
        _status = '${_hits.length} matches in scanned window · '
            '${_next == null ? 'Reached file end' : 'More ranges available'}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    return Scaffold(appBar: AppBar(title: const Text('Large Binary Viewer')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Read-only 1 GiB limit. Stream pages, SHA-256 and bounded 64 MiB hex search windows.'),
        FilledButton(onPressed: _busy ? null : () => _task(_open),
          child: const Text('Open local file')),
        if (_busy) const LinearProgressIndicator(),
        if (file != null) ...[
          Text('${file.length} bytes · page base 0x${_at.toRadixString(16)}'),
          TextField(controller: _offset, enabled: !_busy,
            decoration: const InputDecoration(labelText: 'File offset (hex)')),
          Wrap(spacing: 8, children: [
            OutlinedButton(onPressed: _busy ? null : () => _task(() => _show(_parse())),
              child: const Text('Go')),
            OutlinedButton(onPressed: _busy || _at == 0 ? null :
              () => _task(() => _show((_at - 256).clamp(0, _at).toInt())), child: const Text('Previous')),
            OutlinedButton(onPressed: _busy || _at + 256 >= file.length ? null :
              () => _task(() => _show(_at + 256)), child: const Text('Next')),
            OutlinedButton(onPressed: _busy ? null : () => _task(() async {
              final hash = await PagedBinaryService.hash(file);
              if (mounted) {
                setState(() => _status = 'SHA-256: $hash');
              }
            }), child: const Text('Stream SHA-256')),
          ]),
          const Text('Hex rows use offsets relative to the page base.'),
          SingleChildScrollView(scrollDirection: Axis.horizontal,
            child: SelectableText(_page, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
          TextField(controller: _pattern, enabled: !_busy, maxLength: 768,
            onChanged: (_) => setState(() {
              _next = null;
              _hits = [];
            }), decoration: const InputDecoration(labelText: 'Exact hex pattern')),
          Wrap(spacing: 8, children: [
            OutlinedButton(onPressed: _busy ? null : () => _task(() => _search(_parse())),
              child: const Text('Search from offset')),
            OutlinedButton(onPressed: _busy || _next == null ? null :
              () => _task(() => _search(_next!)), child: const Text('Continue next range')),
          ]),
          if (_hits.isNotEmpty)
            SizedBox(height: 180, child: ListView.builder(itemCount: _hits.length,
              itemBuilder: (context, i) => ListTile(title: Text('0x${_hits[i].toRadixString(16)}'),
                onTap: _busy ? null : () => _task(() => _show(_hits[i]))))),
        ],
        if (_status.isNotEmpty) ...[
          SelectableText(_status),
          TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: _status)),
            child: const Text('Copy status')),
        ],
      ]));
  }
}
