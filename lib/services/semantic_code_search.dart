import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'project_context_search.dart';
import 'project_workspace_service.dart';

typedef EmbeddingBatch = Future<List<List<double>>> Function(List<String> input);

class SemanticHit {
  const SemanticHit(this.evidence, this.similarity);
  final CodeEvidence evidence;
  final double similarity;
}

class SemanticResult {
  const SemanticResult(this.hits, this.filesRead, this.chunks);
  final List<SemanticHit> hits;
  final int filesRead, chunks;
}

class SemanticCodeSearch {
  const SemanticCodeSearch._();
  static const maxChunks = 64;
  static const batchSize = 4;
  static const maxDimensions = 2048;
  static const maxChunkChars = 600;

  static bool eligible(String path) => ProjectWorkspaceService.eligible(path) &&
      RegExp(r'\.(java|kt|smali|dart|cs|il|js|ts)$', caseSensitive: false).hasMatch(path);

  static List<CodeEvidence> chunks(String path, String text) {
    if (!eligible(path) || text.length > ProjectWorkspaceService.maxTextBytes) {
      return [];
    }
    final lines = const LineSplitter().convert(text);
    final result = <CodeEvidence>[];
    var at = 0;
    while (at < lines.length && result.length < 4) {
      final first = at;
      final out = StringBuffer();
      while (at < lines.length && at - first < 12) {
        final prefix = '${at + 1}: ';
        final available = maxChunkChars - out.length - prefix.length - 2;
        if (available < 1 || (out.isNotEmpty && lines[at].length > available)) {
          break;
        }
        final line = lines[at];
        final stop = line.length.clamp(0, available).toInt();
        out.writeln('$prefix${line.substring(0, stop)}${stop < line.length ? '…' : ''}');
        at++;
      }
      if (at == first) {
        at++;
        continue;
      }
      if (lines.getRange(first, at).any((line) => line.trim().isNotEmpty)) {
        result.add(CodeEvidence(path, first + 1, at, out.toString().trimRight()));
      }
    }
    return result;
  }

  static List<double> normalized(List<double> vector) {
    if (vector.isEmpty || vector.length > maxDimensions ||
        vector.any((x) => !x.isFinite || x.abs() > 1e12)) {
      throw const FormatException('Invalid embedding vector');
    }
    final length = math.sqrt(vector.fold<double>(0, (sum, x) => sum + x * x));
    if (!length.isFinite || length <= 0) {
      throw const FormatException('Zero or invalid embedding norm');
    }
    return vector.map((x) => x / length).toList();
  }

  static Future<List<SemanticHit>> rank({
    required String question, required List<CodeEvidence> evidence,
    required EmbeddingBatch embed, bool Function()? cancelled,
  }) async {
    final query = question.trim();
    if (query.isEmpty || query.length > 600 || evidence.isEmpty || evidence.length > maxChunks) {
      throw const FormatException('Enter a question up to 600 characters and bounded source evidence');
    }
    if (evidence.any((e) => !eligible(e.path) || e.text.isEmpty || e.text.length > maxChunkChars)) {
      throw const FormatException('Invalid evidence chunk');
    }
    void check() {
      if (cancelled?.call() == true) {
        throw const FormatException('Semantic search cancelled');
      }
    }
    check();
    final q = await embed([query]);
    if (q.length != 1) {
      throw const FormatException('Unexpected query embedding count');
    }
    final queryVector = normalized(q.single);
    final hits = <SemanticHit>[];
    for (var offset = 0; offset < evidence.length; offset += batchSize) {
      check();
      final batch = evidence.skip(offset).take(batchSize).toList();
      final vectors = await embed(batch.map((e) => e.text).toList());
      if (vectors.length != batch.length) {
        throw const FormatException('Unexpected document embedding count');
      }
      for (var i = 0; i < vectors.length; i++) {
        final vector = normalized(vectors[i]);
        if (vector.length != queryVector.length) {
          throw const FormatException('Embedding dimensions differ');
        }
        var dot = 0.0;
        for (var j = 0; j < vector.length; j++) {
          dot += vector[j] * queryVector[j];
        }
        hits.add(SemanticHit(batch[i], dot.clamp(-1.0, 1.0).toDouble()));
      }
    }
    check();
    hits.sort((a, b) {
      final score = b.similarity.compareTo(a.similarity);
      if (score != 0) {
        return score;
      }
      final path = a.evidence.path.compareTo(b.evidence.path);
      return path != 0 ? path : a.evidence.firstLine.compareTo(b.evidence.firstLine);
    });
    return hits.take(24).toList();
  }

  static Future<SemanticResult> search(String root, String question,
      EmbeddingBatch embed, {bool Function()? cancelled}) async {
    final listing = await ProjectWorkspaceService.list(root);
    final evidence = <CodeEvidence>[];
    var filesRead = 0;
    for (final path in listing.paths.where(eligible).take(32)) {
      if (cancelled?.call() == true) {
        throw const FormatException('Semantic search cancelled');
      }
      if (evidence.length >= maxChunks) {
        break;
      }
      try {
        final text = await ProjectWorkspaceService.read(root, path);
        filesRead++;
        evidence.addAll(chunks(path, text).take(maxChunks - evidence.length));
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
    }
    final hits = await rank(question: question, evidence: evidence, embed: embed,
        cancelled: cancelled);
    return SemanticResult(hits, filesRead, evidence.length);
  }
}
