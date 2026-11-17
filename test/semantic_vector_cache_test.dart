import 'dart:io';
import 'package:droidre_ai_studio/services/ollama_embedding_service.dart';
import 'package:droidre_ai_studio/services/project_context_search.dart';
import 'package:droidre_ai_studio/services/semantic_code_search.dart';
import 'package:droidre_ai_studio/services/semantic_vector_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cache persists unchanged vectors and invalidates model fingerprint', () async {
    final dir = await Directory.systemTemp.createTemp('vector_cache_');
    try {
      final store = SemanticVectorCache(dir);
      final digest = List.filled(64, 'a').join();
      final other = List.filled(64, 'b').join();
      final key = SemanticVectorCache.contentKey('unchanged');
      await store.save('root', 'model', digest, {key: [1.0, 0.0]});
      final previous = await store.load('root', 'model', digest);
      final requested = <String>[];
      final incremental = IncrementalEmbeddings(previous, (inputs) async {
        requested.addAll(inputs);
        return inputs.map((_) => [0.0, 1.0]).toList();
      });
      final vectors = await incremental.embed(['unchanged', 'edited']);
      expect(vectors, [[1.0, 0.0], [0.0, 1.0]]);
      expect(requested, ['edited']);
      expect(incremental.reused, 1);
      expect(incremental.embedded, 1);
      expect(await store.load('root', 'model', other), isEmpty);
      expect(await store.load('another', 'model', digest), isEmpty);
      await store.clear('root', 'model');
      expect(await store.load('root', 'model', digest), isEmpty);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('hybrid ranking uses lexical overlap for tied cosine', () async {
    final hits = await SemanticCodeSearch.rank(question: 'scan',
      evidence: const [
        CodeEvidence('A.java', 1, 1, 'unrelated'),
        CodeEvidence('B.java', 1, 1, 'scan'),
      ], embed: (input) async => input.map((_) => [1.0]).toList(),
      hybrid: true);
    expect(hits.first.evidence.path, 'B.java');
    expect(hits.first.lexical, 1.0);
  });

  test('installed model digest is exact and validated', () {
    final digest = List.filled(64, 'a').join();
    expect(OllamaEmbeddingService.parseDigest(
      '{"models":[{"name":"all-minilm:latest","digest":"$digest"}]}',
      'all-minilm'), digest);
    expect(() => OllamaEmbeddingService.parseDigest(
      '{"models":[{"name":"other","digest":"$digest"}]}', 'all-minilm'),
      throwsFormatException);
  });
}
