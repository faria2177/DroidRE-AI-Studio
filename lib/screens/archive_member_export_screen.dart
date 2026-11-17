import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../models/apk_report.dart';
import '../services/archive_member_export.dart';
import '../services/local_export_service.dart';

class ArchiveMemberExportScreen extends StatefulWidget {
  const ArchiveMemberExportScreen({super.key, required this.report});
  final ApkReport report;

  @override
  State<ArchiveMemberExportScreen> createState() => _ArchiveMemberExportScreenState();
}

class _ArchiveMemberExportScreenState extends State<ArchiveMemberExportScreen> {
  String? _entry;
  String _message = '';
  bool _busy = false;

  Future<void> _save() async {
    final entry = _entry!;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final bytes = await ArchiveMemberExport.read(widget.report, entry);
      if (!mounted) {
        return;
      }
      final saved = await LocalExportService.saveFile(
        dialogTitle: 'Save selected member as a new file',
        fileName: ArchiveMemberExport.outputName(entry),
        bytes: bytes, protectedPath: widget.report.localPath);
      if (mounted) {
        setState(() => _message = saved == null ? 'Export cancelled' :
            'Exported ${bytes.length} bytes\nSHA-256: ${sha256.convert(bytes)}');
      }
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

  @override
  Widget build(BuildContext context) {
    final all = widget.report.entries.where((e) => e.isFile && e.size > 0 &&
        e.size <= ArchiveMemberExport.maxBytes && ArchiveMemberExport.eligible(e.name))
        .map((e) => e.name).toSet().toList()..sort();
    final paths = all.take(250).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Split APK & Framework Member Export')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Export one indexed member without modification. Reimport a split APK '
            'individually for analysis. No merging, installation or automatic execution. '
            'Choose a new output file. Framework binaries can be opened by compatible external tools.'),
        if (all.length > paths.length) const Text('First 250 candidates displayed.'),
        if (paths.isEmpty) const Text('No eligible member up to 80 MiB in the indexed list.'),
        DropdownButtonFormField<String>(initialValue: _entry, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Archive member'),
          items: paths.map((name) => DropdownMenuItem(value: name,
            child: Text(name, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: _busy ? null : (v) => setState(() {
            _entry = v;
            _message = '';
          })),
        FilledButton(onPressed: _busy || _entry == null ? null : _save,
          child: const Text('Export selected member')),
        if (_busy) const LinearProgressIndicator(),
        if (_message.isNotEmpty) SelectableText(_message),
      ]),
    );
  }
}
