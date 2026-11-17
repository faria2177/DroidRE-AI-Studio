import 'package:droidre_ai_studio/services/ollama_embedding_service.dart';
import 'package:droidre_ai_studio/services/project_context_search.dart';
import 'package:droidre_ai_studio/services/semantic_code_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bounded source chunks retain line references', () {
    final snippets = SemanticCodeSearch.chunks('sources/Main.java',
      List.generate(100, (i) => 'line $i').join('\n'));
    expect(snippets.length, 4);
    expect(snippets.first.firstLine, 1);
    expect(snippets.first.lastLine, 12);
    expect(snippets.last.text.length, lessThanOrEqualTo(600));
    expect(SemanticCodeSearch.chunks('settings.json', 'secret'), isEmpty);
  });
  test('cosine retrieval ranks mock vectors', () async {
    const entries = [
      CodeEvidence('A.java', 1, 2, 'unrelated'),
      CodeEvidence('B.java', 3, 4, 'related'),
    ];
    final hits = await SemanticCodeSearch.rank(question: 'query', evidence: entries,
      embed: (input) async => input.map((s) => s == 'unrelated'
        ? [0.0, 1.0] : [3.0, 0.0]).toList());
    expect(hits.first.evidence.path, 'B.java');
    expect(hits.first.similarity, closeTo(1, 1e-12));
  });
  test('rejects malformed or mismatched embeddings', () async {
    expect(() => OllamaEmbeddingService.decode('{"embeddings":[[0,0]]}', 1), throwsFormatException);
    expect(() => OllamaEmbeddingService.decode('{"embeddings":[["x"]]}', 1), throwsFormatException);
    expect(() => OllamaEmbeddingService('arbitrary:cloud'), throwsFormatException);
    await expectLater(SemanticCodeSearch.rank(question: 'query', evidence: const [
      CodeEvidence('A.java', 1, 1, 'demo'),
    ], embed: (input) async => input.first == 'query' ? [[1.0]] : [[1.0, 2.0]]),
      throwsFormatException);
  });
  test('cancellation prevents embedding request', () async {
    var sent = false;
    await expectLater(SemanticCodeSearch.rank(question: 'query', evidence: const [
      CodeEvidence('A.java', 1, 1, 'demo'),
    ], cancelled: () => true, embed: (_) async {
      sent = true;
      return [[1.0]];
    }), throwsFormatException);
    expect(sent, false);
  });
}
