import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/flutter_structure_inspector.dart';
import '../services/local_export_service.dart';

class FlutterStructureDialog extends StatefulWidget {
  const FlutterStructureDialog({super.key, required this.apkPath, required this.entryName});
  final String apkPath, entryName;

  @override
  State<FlutterStructureDialog> createState() => _FlutterStructureDialogState();
}

class _FlutterStructureDialogState extends State<FlutterStructureDialog> {
  late final Future<Map<String, Object?>> _task;
  String _query = '';
  bool _assets = false;
  bool _saving = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _task = FlutterStructureInspector.inspect(widget.apkPath, widget.entryName);
  }

  Future<void> _export(Map<String, Object?> report) async {
    setState(() => _saving = true);
    try {
      final result = await LocalExportService.saveFile(
        dialogTitle: 'Export local Flutter evidence',
        fileName: 'flutter-structure-evidence.json',
        bytes: Uint8List.fromList(utf8.encode(
          const JsonEncoder.withIndent('  ').convert(report))),
        protectedPath: widget.apkPath,
      );
      if (mounted) {
        setState(() => _message = result == null ? 'Export cancelled' : 'Report saved');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, Object?>>(
    future: _task,
    builder: (context, snapshot) {
      final report = snapshot.data;
      final binary = report?['binary'] as Map<String, Object?>?;
      final assets = report?['assets'] as Map<String, Object?>?;
      final rows = ((_assets ? assets?['entries'] : binary?['strings']) as List? ?? [])
          .whereType<Map>().where((item) =>
             '${item['path'] ?? item['text']} ${item['kind']}'
             .toLowerCase().contains(_query.toLowerCase())).toList();
      return AlertDialog(
        title: const Text('Flutter structure evidence'),
        content: SizedBox(width: 660, height: MediaQuery.sizeOf(context).height * 0.58,
          child: report == null
              ? snapshot.hasError
                  ? SelectableText('Analysis failed: ${snapshot.error}')
                  : const Center(child: CircularProgressIndicator())
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Local byte/path evidence only. Strings may contain sensitive data; review before sharing.'),
                  Text('Snapshot: ${binary?['snapshotLayout']} · ${binary?['scannedBytes']} bytes scanned'
                      '${binary?['partial'] == true ? ' · Partial' : ''}'),
                  Text('Assets: ${assets?['assetCount']} · '
                      '${(assets?['packageFolders'] as List?)?.length ?? 0} package folders'
                      '${assets?['partial'] == true ? ' · Partial' : ''}'),
                  SwitchListTile(value: _assets,
                    title: Text(_assets ? 'Asset inventory' : 'Printable strings'),
                    onChanged: (value) => setState(() {
                      _assets = value;
                      _query = '';
                    })),
                  TextField(key: ValueKey(_assets), onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(labelText: 'Search evidence')),
                  Text('${rows.length} matches'),
                  Expanded(child: ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final row = rows[i];
                      return ListTile(dense: true,
                        title: SelectableText('${row['path'] ?? row['text']}'),
                        subtitle: Text(_assets
                            ? '${row['kind']} · ${row['bytes']} bytes'
                            : '${row['fileOffset']} · ${row['kind']}'
                              '${row['truncated'] == true ? ' · clipped' : ''}'),
                      );
                    },
                  )),
                  if (_message.isNotEmpty) Text(_message),
                ])),
        actions: [
          if (report != null)
            TextButton(onPressed: _saving ? null : () => _export(report), child: const Text('Export JSON')),
          if (report != null)
            TextButton(onPressed: () => Clipboard.setData(ClipboardData(
              text: const JsonEncoder.withIndent('  ').convert(report))), child: const Text('Copy JSON')),
          TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Close')),
        ],
      );
    },
  );
}
