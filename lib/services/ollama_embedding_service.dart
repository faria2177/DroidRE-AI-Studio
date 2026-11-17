import 'dart:convert';
import 'dart:io';
import 'semantic_code_search.dart';

class OllamaEmbeddingService {
  OllamaEmbeddingService(this.model) {
    if (!models.contains(model)) {
      throw const FormatException('Select an allowed local embedding model');
    }
  }
  final String model;
  static const models = ['all-minilm', 'nomic-embed-text'];
  static const maxResponse = 1024 * 1024;
  static final endpoint = Uri.parse('http://127.0.0.1:11434/api/embed');
  HttpClient? _active;
  bool _closed = false;

  static List<List<double>> decode(String body, int expected) {
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['embeddings'] is! List) {
      throw const FormatException('Expected Ollama embeddings response');
    }
    final items = decoded['embeddings'] as List;
    if (items.length != expected || expected < 1 || expected > SemanticCodeSearch.batchSize) {
      throw const FormatException('Unexpected embeddings count');
    }
    final vectors = <List<double>>[];
    for (final item in items) {
      if (item is! List || item.isEmpty || item.length > SemanticCodeSearch.maxDimensions ||
          item.any((x) => x is! num)) {
        throw const FormatException('Invalid embeddings response vector');
      }
      final vector = item.cast<num>().map((x) => x.toDouble()).toList();
      SemanticCodeSearch.normalized(vector);
      vectors.add(vector);
    }
    return vectors;
  }

  Future<List<List<double>>> embed(List<String> input) async {
    if (_closed || _active != null || input.isEmpty || input.length > SemanticCodeSearch.batchSize ||
        input.any((s) => s.isEmpty || s.length > SemanticCodeSearch.maxChunkChars)) {
      throw const FormatException('Invalid or cancelled embedding request');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..findProxy = ((_) => 'DIRECT');
    _active = client;
    try {
      return await _request(client, input).timeout(const Duration(seconds: 90));
    } finally {
      client.close(force: true);
      _active = null;
    }
  }

  Future<List<List<double>>> _request(HttpClient client, List<String> input) async {
    final request = await client.postUrl(endpoint);
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'model': model, 'input': input, 'truncate': false, 'keep_alive': '1m',
    }));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw FormatException('Local Ollama HTTP ${response.statusCode}; verify model installation');
    }
    if (response.contentLength > maxResponse) {
      throw const FormatException('Embedding response too large');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      if (chunk.length > maxResponse - bytes.length) {
        throw const FormatException('Embedding response too large');
      }
      bytes.addAll(chunk);
    }
    return decode(utf8.decode(bytes), input.length);
  }

  /// Resolve only the selected installed model's digest from the local tags API.
  static String parseDigest(String body, String model) {
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['models'] is! List) {
      throw const FormatException('Invalid installed-model list');
    }
    final items = decoded['models'] as List;
    if (items.length > 1000) {
      throw const FormatException('Too many installed models');
    }
    final matches = items.whereType<Map>().where((item) =>
      item['name'] == model || item['name'] == '$model:latest').toList();
    if (matches.length != 1 || matches.single['digest'] is! String) {
      throw const FormatException('Selected installed model fingerprint unavailable');
    }
    final digest = (matches.single['digest'] as String).toLowerCase();
    if (!RegExp(r'^(?:sha256:)?[0-9a-f]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid model digest');
    }
    return digest.replaceFirst('sha256:', '');
  }

  Future<String> fingerprint() async {
    if (_closed || _active != null) {
      throw const FormatException('Invalid or cancelled model request');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..findProxy = ((_) => 'DIRECT');
    _active = client;
    try {
      return await (() async {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:11434/api/tags'));
        request.followRedirects = false;
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok ||
            response.contentLength > maxResponse) {
          throw const FormatException('Local model fingerprint unavailable');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (chunk.length > maxResponse - bytes.length) {
            throw const FormatException('Model list exceeds limit');
          }
          bytes.addAll(chunk);
        }
        return parseDigest(utf8.decode(bytes), model);
      })().timeout(const Duration(seconds: 15));
    } finally {
      client.close(force: true);
      _active = null;
    }
  }

  void close() {
    _closed = true;
    _active?.close(force: true);
  }
}
