import 'dart:convert';
import 'analysis_agent.dart';
import 'project_context_search.dart';

/// Check reviewed, line-numbered excerpts against current source text.
/// A match means evidence is still present, not that an AI claim is true.
class AgentEvidenceVerifier {
  const AgentEvidenceVerifier._();
  static String verify(AgentEvidence evidence, String current) {
    if (current.length > 65536 || current.contains('\u0000')) {
      return 'unavailable';
    }
    final code = evidence.code;
    final lines = const LineSplitter().convert(current);
    if (code.firstLine < 1 || code.lastLine < code.firstLine ||
        code.lastLine > lines.length || code.lastLine - code.firstLine > 4) {
      return 'changed';
    }
    final snippets = const LineSplitter().convert(code.text);
    if (snippets.length != code.lastLine - code.firstLine + 1) {
      return 'unavailable';
    }
    var clipped = false;
    for (var i = 0; i < snippets.length; i++) {
      final prefix = '${code.firstLine + i}: ';
      if (!snippets[i].startsWith(prefix)) {
        return 'unavailable';
      }
      var snippet = snippets[i].substring(prefix.length);
      final source = lines[code.firstLine + i - 1];
      if (snippet == source) {
        continue;
      }
      final leading = snippet.startsWith('…');
      final trailing = snippet.endsWith('…');
      if (!leading && !trailing) {
        return 'changed';
      }
      if (leading) {
        snippet = snippet.substring(1);
      }
      if (trailing && snippet.isNotEmpty) {
        snippet = snippet.substring(0, snippet.length - 1);
      }
      if (snippet.isEmpty || !(leading && trailing ? source.contains(snippet) :
          leading ? source.endsWith(snippet) : source.startsWith(snippet))) {
        return 'changed';
      }
      clipped = true;
    }
    return clipped ? 'visible excerpt matches (clipped)' : 'exact lines match';
  }

  static Future<String> check(List<AgentEvidence> evidence,
      Future<String> Function(String path) read) async {
    if (evidence.isEmpty || evidence.length > AnalysisAgent.maxSelected) {
      throw const FormatException('Invalid reviewed evidence set');
    }
    final content = <String, String?>{};
    final out = StringBuffer('Evidence freshness check (not factual claim verification)\n');
    for (final item in evidence) {
      final path = item.code.path;
      if (!ProjectContextSearch.eligible(path)) {
        out.writeln('${item.id}: unavailable');
        continue;
      }
      if (!content.containsKey(path)) {
        try {
          content[path] = await read(path);
        } catch (_) {
          content[path] = null;
        }
      }
      final text = content[path];
      out.writeln('${item.id} $path: ${text == null ? 'unavailable' : verify(item, text)}');
    }
    return out.toString();
  }
}
