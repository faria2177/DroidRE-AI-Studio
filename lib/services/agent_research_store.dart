import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'analysis_agent.dart';

class ResearchPlan {
  const ResearchPlan(this.question, this.queries);
  final String question;
  final List<String> queries;
}

/// Explicit opt-in, one local plan per workspace. No provider credential,
/// report, source snippets, or automatic network requests.
class AgentResearchStore {
  const AgentResearchStore(this.directory);
  final Directory directory;
  static const maxBytes = 16384;
  static Future<AgentResearchStore> appLocal() async =>
      AgentResearchStore(Directory(p.join(
        (await getApplicationSupportDirectory()).path, 'agent-research-v1')));

  File _file(String scope) {
    if (scope.isEmpty || scope.length > 8192) {
      throw const FormatException('Invalid workspace identity');
    }
    final hash = sha256.convert(utf8.encode(scope)).toString();
    return File(p.join(directory.path, '$hash.json'));
  }

  Future<void> save(String scope, ResearchPlan plan) async {
    AnalysisAgent.planPrompt(plan.question);
    final terms = AnalysisAgent.validateQueries(plan.queries);
    final bytes = utf8.encode(jsonEncode({'schema': 1,
      'question': plan.question.trim(), 'queries': terms}));
    if (bytes.length > maxBytes) {
      throw const FormatException('Research plan exceeds storage limit');
    }
    final target = _file(scope);
    await directory.create(recursive: true);
    final temporary = await directory.createTemp('stage-');
    try {
      final file = File(p.join(temporary.path, 'plan.json'));
      await file.writeAsBytes(bytes, flush: true);
      await file.rename(target.path);
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  Future<ResearchPlan?> load(String scope) async {
    final file = _file(scope);
    if (!await file.exists()) {
      return null;
    }
    if (await file.length() > maxBytes) {
      throw const FormatException('Stored plan exceeds limit');
    }
    final bytes = await file.openRead(0, maxBytes + 1)
        .fold<List<int>>([], (a, b) => a..addAll(b));
    if (bytes.length > maxBytes) {
      throw const FormatException('Stored plan exceeds limit');
    }
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map || data['schema'] != 1 || data['question'] is! String ||
        data['queries'] is! List) {
      throw const FormatException('Invalid saved research plan');
    }
    final question = data['question'] as String;
    AnalysisAgent.planPrompt(question);
    final raw = data['queries'] as List;
    if (raw.any((q) => q is! String)) {
      throw const FormatException('Invalid saved search terms');
    }
    return ResearchPlan(question, AnalysisAgent.validateQueries(raw.cast<String>()));
  }

  Future<void> clear(String scope) async {
    final file = _file(scope);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
