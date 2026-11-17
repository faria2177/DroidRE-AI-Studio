import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/split_set_inspector.dart';

class SplitSetScreen extends StatefulWidget {
  const SplitSetScreen({super.key});
  @override
  State<SplitSetScreen> createState() => _SplitSetScreenState();
}

class _SplitSetScreenState extends State<SplitSetScreen> {
  bool _busy = false;
  String _output = '';
  Future<void> _inspect() async {
    setState(() { _busy = true; _output = ''; });
    try {
      final selected = await FilePicker.platform.pickFiles(allowMultiple: true,
        type: FileType.custom, allowedExtensions: ['apk']);
      if (selected == null) {
        return;
      }
      final paths = selected.files.map((f) => f.path).whereType<String>().toList();
      if (paths.length != selected.files.length) {
        throw const FormatException('All files must have local paths');
      }
      final result = await SplitSetInspector.inspect(paths);
      if (mounted) {
        setState(() => _output = const JsonEncoder.withIndent('  ').convert(result));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _output = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Split APK Set Preflight')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Select base and split APKs. Check package, version and split-name consistency. '
        'No merge, installation or signature validation. Use trusted apksigner separately.'),
      FilledButton(onPressed: _busy ? null : _inspect, child: const Text('Select APK set')),
      if (_busy) const LinearProgressIndicator(),
      if (_output.isNotEmpty) ...[
        OutlinedButton(onPressed: () => Clipboard.setData(ClipboardData(text: _output)),
          child: const Text('Copy report')),
        SelectableText(_output),
      ],
    ]),
  );
}
