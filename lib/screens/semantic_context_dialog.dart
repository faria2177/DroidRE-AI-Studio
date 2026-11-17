import 'dart:io';
import 'package:flutter/material.dart';
import '../services/ollama_embedding_service.dart';
import '../services/project_context_search.dart';
import '../services/semantic_code_search.dart';
import '../services/semantic_vector_cache.dart';

class SemanticContextDialog extends StatefulWidget {
  const SemanticContextDialog({super.key, required this.root});
  final String root;
  @override
  State<SemanticContextDialog> createState() => _SemanticContextDialogState();
}

class _SemanticContextDialogState extends State<SemanticContextDialog> {
  final _question = TextEditingController();
  final _chosen = <int>{};
  String _model = OllamaEmbeddingService.models.first;
  SemanticResult? _result;
  OllamaEmbeddingService? _client;
  bool _consent = false, _busy = false, _persist = false, _hybrid = true;
  String _message = '';

  @override
  void dispose() {
    _client?.close();
    _question.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_busy || !_consent) {
      return;
    }
    final question = _question.text.trim();
    if (question.isEmpty || question.length > 600) {
      setState(() => _message = 'Enter a question up to 600 characters.');
      return;
    }
    final client = OllamaEmbeddingService(_model);
    _client = client;
    setState(() {
      _busy = true;
      _result = null;
      _chosen.clear();
      _message = '';
    });
    try {
      final root = await Directory(widget.root).resolveSymbolicLinks();
      final persist = _persist;
      final hybrid = _hybrid;
      final store = persist ? await SemanticVectorCache.appLocal() : null;
      final digest = persist ? await client.fingerprint() : null;
      final previous = store != null
          ? await store.load(root, client.model, digest!) : <String, List<double>>{};
      final incremental = IncrementalEmbeddings(previous, client.embed);
      final result = await SemanticCodeSearch.search(root, question, client.embed,
          documentEmbed: incremental.embed, hybrid: hybrid,
          cancelled: () => !mounted || _client != client);
      if (store != null) {
        if (await client.fingerprint() != digest) {
          throw const FormatException('Model changed during search; retry');
        }
        if (mounted && _client == client) {
          await store.save(root, client.model, digest!, incremental.current);
        }
      }
      if (mounted && _client == client) {
        setState(() {
          _result = result;
          _message = '${incremental.reused} reused · ${incremental.embedded} new chunk vectors';
        });
      }
    } catch (e) {
      if (mounted && _client == client) {
        setState(() => _message = '$e');
      }
    } finally {
      client.close();
      if (mounted && _client == client) {
        setState(() {
          _client = null;
          _busy = false;
        });
      }
    }
  }

  void _cancel() {
    _client?.close();
    setState(() {
      _client = null;
      _busy = false;
      _message = 'Search cancelled';
    });
  }

  Future<void> _clearCache() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final root = await Directory(widget.root).resolveSymbolicLinks();
      final store = await SemanticVectorCache.appLocal();
      await store.clear(root, _model);
      if (mounted) {
        setState(() => _message = 'Selected workspace/model cache cleared');
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

  void _draft() {
    try {
      final indexes = _chosen.toList()..sort();
      final draft = ProjectContextSearch.draft(_question.text,
          indexes.map((i) => _result!.hits[i].evidence));
      Navigator.pop(context, draft);
    } catch (e) {
      setState(() => _message = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return AlertDialog(
      title: const Text('Local semantic code retrieval'),
      content: SizedBox(width: 700, height: MediaQuery.sizeOf(context).height * 0.67,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Ollama loopback: samples up to 32 files / 64 chunks. '
              'Use a trusted local server with cloud disabled. '
              'Sampled code and question are sent to that server. Partial results.'),
          DropdownButtonFormField<String>(initialValue: _model,
            decoration: const InputDecoration(labelText: 'Installed embedding model'),
            items: OllamaEmbeddingService.models.map((name) =>
              DropdownMenuItem(value: name, child: Text(name))).toList(),
            onChanged: _busy ? null : (v) => setState(() {
              _model = v ?? _model;
              _consent = false;
              _result = null;
              _chosen.clear();
            })),
          TextField(controller: _question, enabled: !_busy, maxLength: 600, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Analysis question'),
            onChanged: (_) => setState(() {
              _result = null;
              _chosen.clear();
            })),
          CheckboxListTile(value: _consent, dense: true,
            title: const Text('I trust this server and authorize sampled code for embeddings'),
            onChanged: _busy ? null : (v) => setState(() => _consent = v ?? false)),
          CheckboxListTile(value: _hybrid, dense: true,
            title: const Text('Hybrid keyword + vector ranking'),
            onChanged: _busy ? null : (v) => setState(() {
              _hybrid = v ?? false;
              _result = null;
              _chosen.clear();
            })),
          CheckboxListTile(value: _persist, dense: true,
            title: const Text('Keep local vectors on disk (sensitive derived data)'),
            onChanged: _busy ? null : (v) => setState(() => _persist = v ?? false)),
          TextButton(onPressed: _busy ? null : _clearCache,
            child: const Text('Clear workspace/model cache')),
          OutlinedButton(onPressed: _busy ? (_client != null ? _cancel : null) : !_consent ? null : _search,
            child: Text(_busy ? 'Cancel search' : 'Find relevant code')),
          if (_busy) const LinearProgressIndicator(),
          if (result != null)
            Text('${result.chunks} sampled chunks · ${result.filesRead} files · ${_chosen.length} selected'),
          if (_message.isNotEmpty) Text(_message, maxLines: 3, overflow: TextOverflow.ellipsis),
          Expanded(child: ListView.builder(itemCount: result?.hits.length ?? 0,
            itemBuilder: (context, i) {
              final hit = result!.hits[i];
              final item = hit.evidence;
              return CheckboxListTile(value: _chosen.contains(i),
                onChanged: !_chosen.contains(i) && _chosen.length >= 12 ? null :
                  (v) => setState(() {
                    if (v == true) {
                      _chosen.add(i);
                    } else {
                      _chosen.remove(i);
                    }
                  }),
                title: Text('${item.path}:${item.firstLine}–${item.lastLine} · '
                    'cosine ${hit.similarity.toStringAsFixed(3)} · rank ${hit.score.toStringAsFixed(3)}'),
                subtitle: SelectableText(item.text,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11)));
            })),
        ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(onPressed: _busy || _chosen.isEmpty ? null : _draft,
          child: const Text('Prepare reviewed AI prompt')),
      ],
    );
  }
}
