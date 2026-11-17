import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/native_branch_references.dart';
import '../services/native_llvm_disassembler.dart';
import '../services/elf_symbol_inspector.dart';

class NativeExtendedDialog extends StatefulWidget {
  const NativeExtendedDialog({super.key, required this.apkPath,
    required this.entryName, required this.sectionIndex, this.function});
  final String apkPath, entryName;
  final int sectionIndex;
  final ElfSymbol? function;

  @override
  State<NativeExtendedDialog> createState() => _NativeExtendedDialogState();
}

class _NativeExtendedDialogState extends State<NativeExtendedDialog> {
  final _address = TextEditingController();
  String _output = '';
  bool _busy = false;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _output = '';
    });
    try {
      final result = await action();
      if (mounted) {
        setState(() => _output = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _output = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<String> _incoming() async {
    final raw = _address.text.trim().toLowerCase();
    final target = int.tryParse(raw.startsWith('0x') ? raw.substring(2) : raw, radix: 16);
    if (target == null || target < 0) {
      throw const FormatException('Enter a hexadecimal virtual address');
    }
    final report = await NativeBranchReferences.incoming(widget.apkPath,
        widget.entryName, widget.sectionIndex, target);
    return '${report.references.length} observed direct branches · '
        '${report.scannedWords} words scanned'
        '${report.partial ? ' · Partial' : ''}\n'
        'Linear sweep of selected section only; data and unresolved indirect calls remain.\n\n'
        '${report.references.map((item) => item.line).join('\n')}';
  }

  Future<String> _llvm() async {
    final consent = await showDialog<bool>(context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use external LLVM tool?'),
        content: const Text('Select a trusted llvm-objdump.exe from your Android NDK. '
            'This external parser is not sandboxed. Do not use executables from an APK. '
            'Only analyze trusted input or use an isolated VM.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
        ],
      ));
    if (consent != true || !mounted) {
      return 'Cancelled';
    }
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['exe']);
    final path = picked?.files.single.path;
    if (path == null || !mounted) {
      return 'Cancelled';
    }
    final report = await NativeLlvmDisassembler.inspect(executable: path,
        apkPath: widget.apkPath, entryName: widget.entryName,
        sectionIndex: widget.sectionIndex,
        functionAddress: widget.function?.value, functionSize: widget.function?.size);
    return '${report.architecture} · 0x${report.start.toRadixString(16)}–'
        '0x${report.end.toRadixString(16)}'
        '${report.truncated ? ' · Bounded / truncated' : ''}\n\n${report.output}';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Native analysis'),
    content: SizedBox(width: 660, height: MediaQuery.sizeOf(context).height * 0.55,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _address, enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Target virtual address (hex)')),
        OutlinedButton(onPressed: _busy ? null : () => _run(_incoming),
          child: const Text('Find incoming direct ARM64 branches')),
        if (Platform.isWindows)
          OutlinedButton(onPressed: _busy ? null : () => _run(_llvm),
            child: const Text('LLVM multi-architecture disassembly')),
        if (_busy) const LinearProgressIndicator(),
        Expanded(child: SingleChildScrollView(
          child: SelectableText(_output, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        )),
      ])),
    actions: [
      TextButton(onPressed: _output.isEmpty ? null : () {
        Clipboard.setData(ClipboardData(text: _output));
      }, child: const Text('Copy')),
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Close')),
    ],
  );
}
