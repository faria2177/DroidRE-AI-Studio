import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/external_tool_manager.dart';

class ExternalToolManagerScreen extends StatefulWidget {
  const ExternalToolManagerScreen({super.key});
  @override
  State<ExternalToolManagerScreen> createState() => _ExternalToolManagerScreenState();
}
class _ExternalToolManagerScreenState extends State<ExternalToolManagerScreen> {
  final _paths = <ToolKind, String>{};
  final _results = <ToolKind, String>{};
  bool _trusted = false, _busy = false;
  String _message = '';

  Future<void> _task(Future<void> Function() action) async {
    setState(() { _busy = true; _message = ''; });
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

  Future<void> _detect() async {
    final found = await ExternalToolManager.candidates();
    if (mounted) {
      setState(() {
        _paths.addAll(found);
        _results.clear();
        _trusted = false;
        _message = '${found.length} candidate paths found; verify before use.';
      });
    }
  }

  Future<void> _pick(ToolKind kind) async {
    final path = kind == ToolKind.ghidra ? await FilePicker.platform.getDirectoryPath() :
        (await FilePicker.platform.pickFiles(type: FileType.custom,
          allowedExtensions: ['exe']))?.files.single.path;
    if (mounted && path != null) {
      setState(() {
        _paths[kind] = path;
        _results.remove(kind);
        _trusted = false;
      });
    }
  }

  static const guides = <ToolKind, String>{
    ToolKind.java: 'https://adoptium.net/',
    ToolKind.adb: 'https://developer.android.com/tools/releases/platform-tools',
    ToolKind.llvm: 'https://developer.android.com/ndk/downloads',
    ToolKind.ilspy: 'https://github.com/icsharpcode/ILSpy',
    ToolKind.dotnet: 'https://dotnet.microsoft.com/download',
    ToolKind.ghidra: 'https://ghidra-sre.org/',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Universal Tool Manager')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Check candidate paths and explicit version commands. '
        'File names/version output are not proof of trust or compatibility. '
        'Tools are installed and selected separately; no automatic download.'),
      FilledButton(onPressed: _busy ? null : () => _task(_detect),
        child: const Text('Detect common installation paths')),
      CheckboxListTile(value: _trusted,
        title: const Text('I trust the selected tool executables'),
        onChanged: _busy ? null : (v) => setState(() => _trusted = v ?? false)),
      if (_busy) const LinearProgressIndicator(),
      if (_message.isNotEmpty) SelectableText(_message),
      for (final kind in ToolKind.values)
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ExternalToolManager.name(kind), style: Theme.of(context).textTheme.titleMedium),
            SelectableText(_paths[kind] ?? 'Path not selected'),
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: _busy ? null : () => _task(() => _pick(kind)),
                child: const Text('Select')),
              OutlinedButton(onPressed: _busy || !_trusted || _paths[kind] == null ? null :
                () => _task(() async {
                  final result = await ExternalToolManager.inspect(kind, _paths[kind]!);
                  if (mounted) {
                    setState(() => _results[kind] = result);
                  }
                }), child: const Text('Check version')),
              TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: guides[kind]!)),
                child: const Text('Copy official install link')),
            ]),
            if (_results[kind] != null) SelectableText(_results[kind]!),
          ]))),
    ]),
  );
}
