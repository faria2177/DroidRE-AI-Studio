import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/elf_disassembly_inspector.dart';
import '../services/elf_symbol_inspector.dart';
import '../services/native_branch_references.dart';
import 'native_extended_dialog.dart';

class ElfDisassemblyDialog extends StatefulWidget {
  const ElfDisassemblyDialog({
    super.key,
    required this.apkPath,
    required this.entryName,
    required this.sectionIndex,
    required this.label,
    this.function,
  });

  final String apkPath;
  final String entryName;
  final int sectionIndex;
  final String label;
  final ElfSymbol? function;

  @override
  State<ElfDisassemblyDialog> createState() => _ElfDisassemblyDialogState();
}

class _ElfDisassemblyDialogState extends State<ElfDisassemblyDialog> {
  late Future<ElfDisassemblyPage> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch(0);
  }

  Future<ElfDisassemblyPage> _fetch(int offset) =>
      ElfDisassemblyInspector.inspectEntry(
        widget.apkPath, widget.entryName, widget.sectionIndex,
        offset: offset, function: widget.function,
      );

  void _page(int offset) => setState(() => _future = _fetch(offset));

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: Text('Native: ${widget.label}', maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: size.width > 780 ? 690 : size.width - 92,
        height: size.height * 0.58,
        child: FutureBuilder<ElfDisassemblyPage>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return SelectableText('Disassembly unavailable: ${snapshot.error}');
            }
            final page = snapshot.data!;
            final branches = NativeBranchReferences.outgoing(page.instructions);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Read-only linear sweep, partial ARM64 instruction set. '
                    'Executable sections may contain data. No native code is executed.'),
                const SizedBox(height: 6),
                Text('Bytes ${page.offset}–${page.nextOffset} of ${page.rangeBytes} · '
                    '${page.unsupported} unsupported words'),
                Text('ELF offset: 0x${page.fileOffset.toRadixString(16)}'),
                Text('${branches.length} direct branch targets on this page'),
                if (page.trailingBytes != 0)
                  Text('${page.trailingBytes} trailing bytes do not form an instruction.'),
                const SizedBox(height: 8),
                Expanded(child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(page.text, style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12)),
                  ),
                )),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  OutlinedButton(
                    onPressed: page.hasPrevious
                        ? () => _page((page.offset -
                            ElfDisassemblyInspector.pageInstructions * 4)
                            .clamp(0, page.offset).toInt()) : null,
                    child: const Text('Previous'),
                  ),
                  OutlinedButton(
                    onPressed: page.hasNext ? () => _page(page.nextOffset) : null,
                    child: const Text('Next'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: page.text));
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                  ),
                ]),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => showDialog<void>(context: context,
          builder: (_) => NativeExtendedDialog(apkPath: widget.apkPath,
            entryName: widget.entryName, sectionIndex: widget.sectionIndex,
            function: widget.function)), child: const Text('Native analysis / LLVM')),
        TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Close'))],
    );
  }
}
