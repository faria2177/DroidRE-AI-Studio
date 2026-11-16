import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/elf_section_hex_inspector.dart';
import '../services/elf_section_inspector.dart';

/// Read-only, on-demand hex/ASCII viewer with bounded 256-byte pages.
class ElfSectionHexDialog extends StatefulWidget {
  const ElfSectionHexDialog({
    super.key,
    required this.apkPath,
    required this.entryName,
    required this.section,
  });

  final String apkPath;
  final String entryName;
  final ElfSectionInfo section;

  @override
  State<ElfSectionHexDialog> createState() => _ElfSectionHexDialogState();
}

class _ElfSectionHexDialogState extends State<ElfSectionHexDialog> {
  late Future<ElfSectionHexPreview> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch(0);
  }

  Future<ElfSectionHexPreview> _fetch(int offset) =>
      ElfSectionHexInspector.inspectEntry(
        widget.apkPath,
        widget.entryName,
        widget.section.index,
        sectionOffset: offset,
      );

  void _showPage(int offset) {
    setState(() => _future = _fetch(offset));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dialogWidth = size.width > 780 ? 690.0 : size.width - 92;
    final dialogHeight = size.height > 680 ? 440.0 : size.height * 0.56;

    return AlertDialog(
      title: Text(
        'ELF hex preview: ${widget.section.name}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: FutureBuilder<ElfSectionHexPreview>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: SelectableText(
                  'Cannot preview ELF section: ${snapshot.error}',
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final preview = snapshot.data!;
            final lastByte = preview.sectionOffset + preview.bytesShown;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Section #${preview.sectionIndex} · '
                    '${preview.sectionSize} bytes · '
                    'viewing ${preview.sectionOffset}–$lastByte'),
                const SizedBox(height: 4),
                Text('Absolute ELF file offset: '
                    '0x${preview.fileOffset.toRadixString(16)}'),
                const SizedBox(height: 10),
                Expanded(
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SelectableText(
                          preview.hexDump,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton(
                      onPressed: preview.hasPrevious
                          ? () => _showPage(
                              preview.sectionOffset -
                                  ElfSectionHexInspector.pageBytes)
                          : null,
                      child: const Text('Previous'),
                    ),
                    OutlinedButton(
                      onPressed: preview.hasNext
                          ? () => _showPage(lastByte)
                          : null,
                      child: const Text('Next'),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy hex'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: preview.hexDump));
                      },
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
