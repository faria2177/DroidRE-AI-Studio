import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/apk_report.dart';
import '../services/apk_security_review.dart';
import '../services/local_export_service.dart';

class ApkSecurityScreen extends StatefulWidget {
  const ApkSecurityScreen({super.key, required this.active, required this.projects,
    this.comparison = false});
  final ApkReport active;
  final List<ApkReport> projects;
  final bool comparison;

  @override
  State<ApkSecurityScreen> createState() => _ApkSecurityScreenState();
}

class _ApkSecurityScreenState extends State<ApkSecurityScreen> {
  ApkReport? _baseline;
  Map<String, Object?>? _result;
  bool _busy = false;
  String _error = '';

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _result = null;
      _error = '';
    });
    try {
      final result = widget.comparison
          ? await ApkSecurityReview.compare(_baseline!, widget.active)
          : await ApkSecurityReview.inspect(widget.active);
      if (mounted) {
        setState(() => _result = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final saved = await LocalExportService.saveFile(
        dialogTitle: 'Save local analysis report',
        fileName: widget.comparison ? 'apk-version-diff.json' : 'apk-security-review.json',
        bytes: Uint8List.fromList(utf8.encode(
            const JsonEncoder.withIndent('  ').convert(_result))),
        protectedPath: widget.active.localPath,
      );
      if (mounted && saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report saved')));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _result;
    final differences = report?['differences'];
    final review = report?['permissionReview'];
    final signature = report?['signature'];
    return Scaffold(
      appBar: AppBar(title: Text(widget.comparison ? 'APK Version Diff' : 'APK Security Review')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.active.fileName, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(widget.comparison
            ? 'Compare an older imported APK with this candidate. Byte-level member evidence, not semantic source diff.'
            : 'Offline permission and signing structure review. Not a malware scanner or cryptographic signature verifier.'),
        if (widget.comparison) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<ApkReport>(
            initialValue: _baseline,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Baseline APK', border: OutlineInputBorder()),
            items: widget.projects.where((item) => item.id != widget.active.id &&
                item.fileName.toLowerCase().endsWith('.apk')).map((item) =>
                  DropdownMenuItem(value: item, child: Text(item.fileName, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: _busy ? null : (value) => setState(() {
              _baseline = value;
              _result = null;
            }),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _busy || (widget.comparison && _baseline == null)
            ? null : _run, icon: const Icon(Icons.fact_check_outlined),
          label: Text(widget.comparison ? 'Compare APKs' : 'Inspect security evidence')),
        if (_busy) const LinearProgressIndicator(),
        if (_error.isNotEmpty) SelectableText(_error),
        if (report != null) ...[
          const SizedBox(height: 12),
          Text(report['partial'] == true ? 'Partial evidence' : 'Bounded inspection complete',
              style: Theme.of(context).textTheme.titleMedium),
          if (signature is Map)
            Card(child: ListTile(
              title: Text('Signing block: ${signature['status']}'),
              subtitle: Text('${signature['schemes']}\nCryptographically verified: NO'),
            )),
          if (review is List)
            for (final item in review.whereType<Map>())
              ListTile(title: Text('${item['permission']}'), subtitle: Text('${item['review']}')),
          if (differences is List) ...[
            Text('${differences.length} differences / unverified · '
                '${report['verifiedUnchanged']} hash-verified unchanged'),
            Text('Permissions added: ${report['permissionsAdded']}\n'
                'Permissions removed: ${report['permissionsRemoved']}'),
            for (final item in differences.take(200).whereType<Map>())
              ListTile(title: Text('${item['path']}'), subtitle: Text('${item['status']}')),
            if (differences.length > 200)
              const Text('First 200 entries displayed; JSON contains full bounded results.'),
          ],
          OutlinedButton.icon(onPressed: _busy ? null : _export,
            icon: const Icon(Icons.save_alt), label: const Text('Export JSON report')),
          SelectableText('${report['scope']}'),
        ],
      ]),
    );
  }
}
