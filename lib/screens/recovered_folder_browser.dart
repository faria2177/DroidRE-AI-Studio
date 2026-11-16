import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/source_recovery_folder_service.dart';
import '../services/saf_source_recovery_service.dart';

/// Browse code generated into Android app-specific external storage.
class RecoveredFolderBrowserScreen extends StatefulWidget {
  const RecoveredFolderBrowserScreen({
    super.key,
    this.folderPath,
    this.folderUri,
    this.folderLabel,
  }) : assert(folderPath != null || folderUri != null);

  final String? folderPath;
  final String? folderUri;
  final String? folderLabel;

  @override
  State<RecoveredFolderBrowserScreen> createState() =>
      _RecoveredFolderBrowserScreenState();
}

class _RecoveredFolderBrowserScreenState
    extends State<RecoveredFolderBrowserScreen> {
  late Future<List<String>> files;

  @override
  void initState() {
    super.initState();
    files = widget.folderUri == null
        ? SourceRecoveryFolderService.listRelativeFiles(widget.folderPath!)
        : SafSourceRecoveryService.listFiles(widget.folderUri!);
  }

  void _openFile(String relativePath) {
    final preview = widget.folderUri == null
        ? SourceRecoveryFolderService.previewFile(
            widget.folderPath!, relativePath)
        : SafSourceRecoveryService.readFile(
            widget.folderUri!, relativePath);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(relativePath,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: 650,
          height: 420,
          child: FutureBuilder<String>(
            future: preview,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Cannot read file: ${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return SingleChildScrollView(
                child: SelectableText(snapshot.data!,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12)),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Generated Source Files'),
      actions: [
        IconButton(
          tooltip: 'Copy folder path',
          icon: const Icon(Icons.copy_all_outlined),
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: widget.folderLabel ??
                  widget.folderPath ?? widget.folderUri ?? ''),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Folder path copied')),
              );
            }
          },
        ),
      ],
    ),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.folderUri != null
                  ? 'Generated in a user-selected File Manager folder '
                      'outside Android/data using Android document access. '
                      'The project remains offline and read-only.'
                  : 'Generated in app-specific storage. '
                      'No device-wide storage permission is required.'),
              const SizedBox(height: 6),
              SelectableText(widget.folderLabel ??
                  widget.folderPath ?? 'Recovered folder',
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12)),
              const SizedBox(height: 6),
              const Text('Java-like .txt files are NON-COMPILABLE, '
                  'Dalvik .txt files are NOT rebuildable Smali. '
                  'See README.md and REPORT.json for coverage.'),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<String>>(
            future: files,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Unable to list generated files: '
                      '${snapshot.error}'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final paths = snapshot.data!;
              if (paths.isEmpty) {
                return const Center(child: Text(
                    'No generated files found at this path.'));
              }
              return ListView.builder(
                itemCount: paths.length,
                itemBuilder: (context, index) {
                  final path = paths[index];
                  return ListTile(
                    dense: true,
                    leading: Icon(path.endsWith('.bin')
                        ? Icons.data_object_outlined
                        : Icons.code_outlined),
                    title: Text(path, maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openFile(path),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
