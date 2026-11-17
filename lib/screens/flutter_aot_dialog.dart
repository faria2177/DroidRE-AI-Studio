import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/flutter_aot_inspector.dart';
import 'elf_section_hex_dialog.dart';
import 'flutter_structure_dialog.dart';

class FlutterAotDialog extends StatefulWidget {
  const FlutterAotDialog({
    super.key,
    required this.apkPath,
    required this.entryName,
  });

  final String apkPath;
  final String entryName;

  @override
  State<FlutterAotDialog> createState() => _FlutterAotDialogState();
}

class _FlutterAotDialogState extends State<FlutterAotDialog> {
  late final Future<FlutterAotReport> _report;

  @override
  void initState() {
    super.initState();
    _report = FlutterAotInspector.inspectEntry(widget.apkPath, widget.entryName);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return FutureBuilder<FlutterAotReport>(
      future: _report,
      builder: (context, snapshot) {
        final report = snapshot.data;
        return AlertDialog(
          title: const Text('Flutter AOT snapshot analysis'),
          content: SizedBox(
            width: size.width > 780 ? 690 : size.width - 92,
            height: size.height * 0.58,
            child: report == null
                ? snapshot.hasError
                    ? SelectableText('Snapshot analysis unavailable: ${snapshot.error}')
                    : const Center(child: CircularProgressIndicator())
                : ListView(children: [
                    const Text('Read-only snapshot symbol mapping. '
                        'No Dart object deserialization or original source recovery.'),
                    const SizedBox(height: 8),
                    SelectableText('${widget.entryName}\n${report.architecture}'),
                    Text('Layout: ${report.layout} · '
                        '${report.scannedSymbols} symbol records inspected'
                        '${report.partial ? ' · Partial evidence' : ''}'),
                    for (final warning in report.warnings)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(warning),
                      ),
                    for (final region in report.regions)
                      Card(child: ExpansionTile(
                        title: Text(region.symbol.name),
                        subtitle: Text('${region.role} · ${region.section.name}'),
                        children: [
                          ListTile(
                            title: SelectableText(
                              'VA: 0x${region.symbol.value.toRadixString(16)}\n'
                              'File: 0x${region.fileOffset.toRadixString(16)}\n'
                              'Size: ${region.symbol.size == 0 ? 'unknown' : region.symbol.size}'),
                            subtitle: Text(region.snapshotMagic
                                ? 'Data signature observed'
                                : 'No data signature asserted'),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(region.headerHex,
                              style: const TextStyle(fontFamily: 'monospace')),
                          ),
                          TextButton.icon(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => ElfSectionHexDialog(
                                apkPath: widget.apkPath,
                                entryName: widget.entryName,
                                section: region.section,
                              ),
                            ),
                            icon: const Icon(Icons.code),
                            label: const Text('Open containing section hex'),
                          ),
                        ],
                      )),
                  ]),
          ),
          actions: [
            TextButton(onPressed: () => showDialog<void>(context: context,
              builder: (_) => FlutterStructureDialog(apkPath: widget.apkPath,
                entryName: widget.entryName)), child: const Text('Strings & assets')),
            if (report != null)
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                    text: const JsonEncoder.withIndent('  ').convert(report.toJson()),
                  ));
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy JSON'),
              ),
            TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
          ],
        );
      },
    );
  }
}
