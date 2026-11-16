import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/source_recovery_folder_service.dart';

/// Browse code generated into Android app-specific external storage.
class RecoveredFolderBrowserScreen extends StatefulWidget {
  const RecoveredFolderBrowserScreen({
    super.key,
    required this.folderPath,
  });

  final String folderPath;

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
    files = SourceRecoveryFolderService.listRelativeFiles(widget.folderPath);
  }

  void _openFile(String relativePath) {
    final preview = SourceRecoveryFolderService.previewFile(
        widget.folderPath, relativePath);
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
              ClipboardData(text: widget.folderPath),
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
              const Text('Generated locally in the Android app-specific '
                  'storage folder. No APK upload or device-wide storage '
                  'permission is required.'),
              const SizedBox(height: 6),
              SelectableText(widget.folderPath,
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
