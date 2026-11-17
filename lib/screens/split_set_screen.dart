import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/split_set_inspector.dart';
import '../services/apk_signer_verification.dart';

class SplitSetScreen extends StatefulWidget {
  const SplitSetScreen({super.key});
  @override
  State<SplitSetScreen> createState() => _SplitSetScreenState();
}

class _SplitSetScreenState extends State<SplitSetScreen> {
  bool _busy = false;
  String _output = '';
  String? _java, _jar;
  bool _trusted = false;
  List<String> _paths = [];
  Future<void> _inspect() async {
    setState(() { _busy = true; _output = ''; _paths = []; });
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
        setState(() {
          _paths = paths;
          _output = const JsonEncoder.withIndent('  ').convert(result);
        });
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
  Future<void> _pickTool(bool java) async {
    final selected = await FilePicker.platform.pickFiles(type: FileType.custom,
      allowedExtensions: [java ? 'exe' : 'jar']);
    final path = selected?.files.single.path;
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

  Future<void> _verifySigners() async {
    if (_busy || !_trusted || _paths.isEmpty) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ApkSignerVerification.verifySet(
        java: _java!, jar: _jar!, apks: _paths);
      if (mounted) {
        setState(() => _output = '$_output\n\nSDK signature verification:\n'
          '${const JsonEncoder.withIndent('  ').convert(result)}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _output = '$_output\n\nVerification unsuccessful: $e');
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
        'No merge or installation. Optional Windows SDK signature verification below.'),
      FilledButton(onPressed: _busy ? null : _inspect, child: const Text('Select APK set')),
      if (Platform.isWindows) ...[
        const SizedBox(height: 12),
        const Text('Optional SDK signature verification: choose trusted JDK and build-tools/lib/apksigner.jar.'),
        OutlinedButton(onPressed: _busy ? null : () => _pickTool(true), child: Text(_java ?? 'Select java.exe')),
        OutlinedButton(onPressed: _busy ? null : () => _pickTool(false), child: Text(_jar ?? 'Select apksigner.jar')),
        CheckboxListTile(value: _trusted, title: const Text('I trust the selected SDK/JDK and authorize verification'),
          onChanged: _busy ? null : (v) => setState(() => _trusted = v ?? false)),
        FilledButton(onPressed: _busy || !_trusted || _paths.isEmpty || _java == null || _jar == null ? null : _verifySigners,
          child: const Text('Verify signatures and compare signer sets')),
      ],
      if (_busy) const LinearProgressIndicator(),
      if (_output.isNotEmpty) ...[
        OutlinedButton(onPressed: () => Clipboard.setData(ClipboardData(text: _output)),
          child: const Text('Copy report')),
        SelectableText(_output),
      ],
    ]),
  );
}
