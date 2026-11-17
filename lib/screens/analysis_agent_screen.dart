import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai_chat_service.dart';
import '../services/analysis_agent.dart';
import '../services/agent_evidence_verifier.dart';
import '../services/project_workspace_service.dart';
import '../services/saf_source_recovery_service.dart';
import '../services/local_export_service.dart';
import '../services/project_context_search.dart';

class AnalysisAgentScreen extends StatefulWidget {
  const AnalysisAgentScreen({super.key, required this.selection, this.root, this.uri});
  final AiSelection selection;
  final String? root, uri;

  @override
  State<AnalysisAgentScreen> createState() => _AnalysisAgentScreenState();
}

class _AnalysisAgentScreenState extends State<AnalysisAgentScreen> {
  final _question = TextEditingController();
  final _queries = TextEditingController();
  final _client = AiChatService();
  final _selected = <int>{};
  List<AgentEvidence> _evidence = [];
  List<AgentEvidence> _reviewed = [];
  String _planPrompt = '', _reportPrompt = '', _report = '', _message = '';
  bool _busy = false, _cancelled = false;
  int _step = 0;

  @override
  void dispose() {
    _cancelled = true;
    _client.close();
    _question.dispose();
    _queries.dispose();
    super.dispose();
  }

  Future<void> _task(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _cancelled = false;
      _message = '';
    });
    try {
      await action();
    } catch (e) {
      if (mounted && !_cancelled) {
        setState(() => _message = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _reset() {
    setState(() {
      _step = 0;
      _planPrompt = '';
      _reportPrompt = '';
      _report = '';
      _queries.clear();
      _evidence = [];
      _reviewed = [];
      _selected.clear();
      _message = '';
    });
  }

  void _preparePlan() {
    try {
      final prompt = AnalysisAgent.planPrompt(_question.text);
      setState(() {
        _planPrompt = prompt;
        _step = 1;
        _message = '';
      });
    } catch (e) {
      setState(() => _message = '$e');
    }
  }

  Future<String> _send(String prompt) => _client.complete(
    endpoint: widget.selection.endpoint, model: widget.selection.model,
    apiKey: widget.selection.apiKey, prompt: prompt);

  Future<void> _createPlan() async {
    final result = await _send(_planPrompt);
    final queries = AnalysisAgent.parsePlan(result);
    if (mounted && !_cancelled) {
      setState(() {
        _queries.text = queries.join('\n');
        _step = 2;
      });
    }
  }

  void _manualPlan() {
    setState(() {
      _queries.clear();
      _step = 2;
      _message = 'Enter one to three literal code search terms, one per line.';
    });
  }

  Future<void> _collect() async {
    final terms = AnalysisAgent.validateQueries(_queries.text.split('\n'));
    setState(() {
      _evidence = [];
      _selected.clear();
      _reviewed = [];
      _reportPrompt = '';
      _report = '';
    });
    final items = await AnalysisAgent.collect(terms, (term) =>
      widget.uri != null ? ProjectContextSearch.saf(widget.uri!, term) :
        ProjectContextSearch.local(widget.root!, term),
      cancelled: () => !mounted || _cancelled,
      onStep: (i) {
        if (mounted) {
          setState(() => _message = 'Local search $i/${terms.length}');
        }
      });
    if (mounted && !_cancelled) {
      setState(() {
        _evidence = items;
        _step = items.isEmpty ? 2 : 3;
        _message = items.isEmpty ? 'No evidence found. Edit search terms and retry.' :
          '${items.length} candidate excerpts. Coverage is partial.';
      });
    }
  }

  void _prepareReport() {
    try {
      final indexes = _selected.toList()..sort();
      final reviewed = indexes.map((i) => _evidence[i]).toList();
      final prompt = AnalysisAgent.reportPrompt(_question.text, reviewed);
      setState(() {
        _reviewed = reviewed;
        _reportPrompt = prompt;
        _step = 4;
        _message = '';
      });
    } catch (e) {
      setState(() => _message = '$e');
    }
  }

  Future<void> _completeReport() async {
    final raw = await _send(_reportPrompt);
    final report = AnalysisAgent.parseReport(raw, _reviewed);
    if (mounted && !_cancelled) {
      setState(() {
        _report = AnalysisAgent.render(report, _question.text,
          '${widget.selection.endpoint.name} / ${widget.selection.model}', _reviewed);
        _step = 5;
      });
    }
  }

  Future<void> _verifyEvidence() async {
    final result = await AgentEvidenceVerifier.check(_reviewed, (path) =>
      widget.uri != null ? SafSourceRecoveryService.readFile(widget.uri!, path) :
        ProjectWorkspaceService.read(widget.root!, path));
    if (mounted) {
      setState(() => _message = result);
    }
  }

  Future<void> _exportReport() async {
    final saved = await LocalExportService.saveFile(
      dialogTitle: 'Save reviewed report (choose new filename)',
      fileName: 'droidre-analysis-report.txt',
      bytes: Uint8List.fromList(utf8.encode(_report)));
    if (mounted) {
      setState(() => _message = saved == null ? 'Export cancelled' : 'Report exported');
    }
  }

  Widget _review(String prompt) => Card(child: Padding(
    padding: const EdgeInsets.all(12), child: SelectableText(prompt)));

  @override
  Widget build(BuildContext context) {
    final provider = '${widget.selection.endpoint.name} / ${widget.selection.model}';
    return Scaffold(
      appBar: AppBar(title: const Text('AI Analysis Agent')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(provider, style: Theme.of(context).textTheme.titleMedium),
        const Text('Review-gated research: plan → local search → select evidence → '
          'review report prompt → report. No file writes, shell, automatic fallback or background agent.'),
        Text('Stage ${_step + 1}/6'),
        if (_busy) const LinearProgressIndicator(),
        if (_message.isNotEmpty) SelectableText(_message),
        if (_step == 0) ...[
          TextField(controller: _question, maxLength: 1000,
            minLines: 2, maxLines: 4,
            decoration: const InputDecoration(labelText: 'Research question')),
          FilledButton(onPressed: _preparePlan, child: const Text('Prepare search plan request')),
        ],
        if (_step == 1) ...[
          const Text('Review this exact prompt. Sending it contacts the selected provider; '
            'the plan request contains the question, not source snippets.'),
          _review(_planPrompt),
          FilledButton(onPressed: _busy ? null : () => _task(_createPlan),
            child: const Text('Approve and request AI search plan')),
          OutlinedButton(onPressed: _busy ? null : _manualPlan,
            child: const Text('Use manual search terms instead')),
        ],
        if (_step == 2) ...[
          const Text('Review/edit the proposed literal queries. Search reads only the chosen workspace.'),
          TextField(controller: _queries, enabled: !_busy, maxLength: 245,
            minLines: 3, maxLines: 3,
            decoration: const InputDecoration(labelText: 'One to three search terms, one per line')),
          FilledButton(onPressed: _busy ? null : () => _task(_collect),
            child: const Text('Run approved local searches')),
          if (_busy) OutlinedButton(onPressed: _cancelled ? null : () => setState(() {
            _cancelled = true;
            _message = 'Stopping after current bounded local search';
          }), child: const Text('Stop research')),
        ],
        if (_step == 3) ...[
          Text('Select up to 12 excerpts after checking for sensitive content. ${_selected.length} selected.'),
          for (var i = 0; i < _evidence.length; i++)
            CheckboxListTile(value: _selected.contains(i),
              onChanged: !_selected.contains(i) && _selected.length >= 12 ? null :
                (v) => setState(() {
                  if (v == true) {
                    _selected.add(i);
                  } else {
                    _selected.remove(i);
                  }
                }),
              title: Text('${_evidence[i].id} · ${_evidence[i].code.path}:${_evidence[i].code.firstLine}–${_evidence[i].code.lastLine}'),
              subtitle: SelectableText(_evidence[i].code.text)),
          FilledButton(onPressed: _selected.isEmpty ? null : _prepareReport,
            child: const Text('Prepare evidence report prompt')),
          TextButton(onPressed: () => setState(() => _step = 2),
            child: const Text('Revise search terms')),
        ],
        if (_step == 4) ...[
          const Text('Review all text below. The selected provider receives these snippets '
            'only after you approve. Citation IDs are checked but claims still need review.'),
          _review(_reportPrompt),
          FilledButton(onPressed: _busy ? null : () => _task(_completeReport),
            child: const Text('Approve and generate evidence report')),
          TextButton(onPressed: _busy ? null : () => setState(() => _step = 3),
            child: const Text('Change evidence selection')),
        ],
        if (_step == 5) ...[
          _review(_report),
          OutlinedButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: _report)),
            icon: const Icon(Icons.copy), label: const Text('Copy evidence report')),
          OutlinedButton.icon(onPressed: _busy ? null : () => _task(_verifyEvidence),
            icon: const Icon(Icons.fact_check_outlined), label: const Text('Recheck evidence against current files')),
          OutlinedButton.icon(onPressed: _busy ? null : () => _task(_exportReport),
            icon: const Icon(Icons.save_alt), label: const Text('Export evidence report')),
          TextButton(onPressed: _busy ? null : () => setState(() {
            _report = '';
            _step = 2;
          }), child: const Text('Refine research using new search terms')),
          for (final item in _reviewed)
            ExpansionTile(title: Text('${item.id} · ${item.code.path}:${item.code.firstLine}'),
              children: [SelectableText(item.code.text)]),
        ],
        if (_step > 0)
          TextButton(onPressed: _busy ? null : _reset, child: const Text('Start new research')),
        const Text('Questions, plan, evidence, keys and report remain session-only in this screen. '
          'Provider retention is governed by the selected service.'),
      ]),
    );
  }
}
