import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'semantic_code_search.dart';

/// Opt-in app-local cache. No source text, questions, or file names are stored.
class SemanticVectorCache {
  const SemanticVectorCache(this.directory);
  final Directory directory;
  static const maxBytes = 4 * 1024 * 1024;
  static const maxEntries = SemanticCodeSearch.maxChunks;
  static Future<SemanticVectorCache> appLocal() async =>
      SemanticVectorCache(Directory(p.join(
        (await getApplicationSupportDirectory()).path, 'semantic-vectors-v1')));

  static String contentKey(String text) =>
      sha256.convert(utf8.encode(text)).toString();
  static bool validDigest(String value) =>
      RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

  File _file(String workspace, String model) => File(p.join(directory.path,
      '${contentKey(jsonEncode([workspace, model]))}.json'));

  Future<Map<String, List<double>>> load(
      String workspace, String model, String digest) async {
    if (!validDigest(digest)) {
      throw const FormatException('Invalid model fingerprint');
    }
    final file = _file(workspace, model);
    if (!await file.exists() || await file.length() > maxBytes) {
      return {};
    }
    try {
      final bytes = await file.openRead(0, maxBytes + 1)
          .fold<List<int>>([], (a, b) => a..addAll(b));
      if (bytes.length > maxBytes) {
        return {};
      }
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map || json['schema'] != 1 || json['digest'] != digest ||
          json['vectors'] is! Map) {
        return {};
      }
      final entries = json['vectors'] as Map;
      if (entries.length > maxEntries) {
        return {};
      }
      final result = <String, List<double>>{};
      int? dimensions;
      for (final entry in entries.entries) {
        final key = entry.key;
        final raw = entry.value;
        if (key is! String || !validDigest(key) || raw is! List ||
            raw.isEmpty || raw.length > SemanticCodeSearch.maxDimensions ||
            raw.any((x) => x is! num)) {
          return {};
        }
        final vector = SemanticCodeSearch.normalized(
          raw.cast<num>().map((x) => x.toDouble()).toList());
        dimensions ??= vector.length;
        if (dimensions != vector.length) {
          return {};
        }
        result[key] = vector;
      }
      return result;
    } on FormatException {
      return {};
    }
  }

  Future<void> save(String workspace, String model, String digest,
      Map<String, List<double>> vectors) async {
    if (!validDigest(digest) || vectors.length > maxEntries ||
        vectors.keys.any((key) => !validDigest(key))) {
      throw const FormatException('Invalid cache scope');
    }
    final normalized = <String, List<double>>{};
    int? dimensions;
    for (final entry in vectors.entries) {
      final vector = SemanticCodeSearch.normalized(entry.value);
      dimensions ??= vector.length;
      if (dimensions != vector.length) {
        throw const FormatException('Inconsistent cached vector dimensions');
      }
      normalized[entry.key] = vector;
    }
    final bytes = utf8.encode(jsonEncode({
      'schema': 1, 'digest': digest, 'vectors': normalized,
    }));
    if (bytes.length > maxBytes) {
      throw const FormatException('Vector cache exceeds limit');
    }
    await directory.create(recursive: true);
    final stage = await directory.createTemp('stage-');
    try {
      final file = File(p.join(stage.path, 'vectors.json'));
      await file.writeAsBytes(bytes, flush: true);
      await file.rename(_file(workspace, model).path);
    } finally {
      await stage.delete(recursive: true);
    }
  }

  Future<void> clear(String workspace, String model) async {
    final file = _file(workspace, model);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// Reuses only unchanged chunks; a completed search replaces the previous sample.
/// The query embedding is always fresh and never cached.
class IncrementalEmbeddings {
  IncrementalEmbeddings(this.previous, this.remote);
  final Map<String, List<double>> previous;
  final EmbeddingBatch remote;
  final current = <String, List<double>>{};
  int reused = 0, embedded = 0;

  Future<List<List<double>>> embed(List<String> input) async {
    final keys = input.map(SemanticVectorCache.contentKey).toList();
    final missing = <String, String>{};
    for (var i = 0; i < input.length; i++) {
      final key = keys[i];
      final known = current[key] ?? previous[key];
      if (known != null) {
        current[key] = known;
        reused++;
      } else {
        missing[key] = input[i];
      }
    }
    if (missing.isNotEmpty) {
      final vectors = await remote(missing.values.toList());
      if (vectors.length != missing.length) {
        throw const FormatException('Unexpected embedding count');
      }
      var i = 0;
      for (final key in missing.keys) {
        current[key] = SemanticCodeSearch.normalized(vectors[i++]);
        embedded++;
      }
    }
    return keys.map((key) => current[key]!).toList();
  }
}
