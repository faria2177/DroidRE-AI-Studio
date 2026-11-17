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

  void close() {
    _closed = true;
    _active?.close(force: true);
  }
}
