import 'package:flutter/material.dart';

import '../services/project_context_search.dart';

class ProjectContextDialog extends StatefulWidget {
  const ProjectContextDialog({super.key, this.folderPath, this.folderUri})
      : assert(folderPath != null || folderUri != null);
  final String? folderPath, folderUri;

  @override
  State<ProjectContextDialog> createState() => _ProjectContextDialogState();
}

class _ProjectContextDialogState extends State<ProjectContextDialog> {
  final _query = TextEditingController();
  final _question = TextEditingController(text: 'Explain this code and its role in the application.');
  final _chosen = <int>{};
  CodeSearchResult? _result;
  bool _busy = false, _ranked = false;
  String _message = '';

  @override
  void dispose() {
    _query.dispose();
    _question.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_busy) {
      return;
    }
    final keyword = _query.text;
    setState(() {
      _busy = true;
      _chosen.clear();
      _result = null;
      _message = '';
    });
    try {
      final result = widget.folderUri != null
          ? await ProjectContextSearch.saf(widget.folderUri!, keyword, ranked: _ranked)
          : await ProjectContextSearch.local(widget.folderPath!, keyword, ranked: _ranked);
      if (mounted) {
        setState(() => _result = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _draft() {
    try {
      final indexes = _chosen.toList()..sort();
      final text = ProjectContextSearch.draft(_question.text,
          indexes.map((i) => _result!.matches[i]));
      Navigator.pop(context, text);
    } catch (error) {
      setState(() => _message = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return AlertDialog(
      title: const Text('Local code search & AI context'),
      content: SizedBox(width: 680, height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Search local recovered text. Up to 500 files / 4 MiB. '
              'Select up to 12 snippets; nothing is sent automatically.'),
          CheckboxListTile(value: _ranked, title: const Text('Rank multiple search terms'),
            onChanged: _busy ? null : (v) => setState(() {
              _ranked = v ?? false;
              _result = null;
              _chosen.clear();
            })),
          TextField(controller: _query, enabled: !_busy,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(labelText: _ranked ? 'Question or keywords' : 'Keyword or exact phrase')),
          OutlinedButton(onPressed: _busy ? null : _search, child: const Text('Search local files')),
          if (_busy) const LinearProgressIndicator(),
          if (result != null)
            Text('${result.matches.length} excerpts · ${result.filesRead} files read'
                '${result.partial ? ' · Partial coverage' : ''} · ${_chosen.length} selected'),
          Expanded(child: ListView.builder(
            itemCount: result?.matches.length ?? 0,
            itemBuilder: (context, i) {
              final match = result!.matches[i];
              return CheckboxListTile(
                value: _chosen.contains(i),
                onChanged: !_chosen.contains(i) && _chosen.length >= 12 ? null : (v) =>
                  setState(() {
                    if (v == true) {
                      _chosen.add(i);
                    } else {
                      _chosen.remove(i);
                    }
                  }),
                title: Text('${match.path}:${match.firstLine}–${match.lastLine}'),
                subtitle: SelectableText(match.text,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              );
            },
          )),
          TextField(controller: _question, minLines: 1, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Analysis question')),
          if (_message.isNotEmpty) Text(_message),
        ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy || _chosen.isEmpty ? null : _draft,
          child: const Text('Prepare reviewable AI prompt')),
      ],
    );
  }
}
