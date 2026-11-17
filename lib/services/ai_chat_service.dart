import 'dart:convert';

import 'package:http/http.dart' as http;

class AiEndpoint {
  const AiEndpoint({
    required this.name,
    required this.url,
    required this.defaultModel,
    this.description = '',
    this.protocol = AiProtocol.chat,
    this.local = false,
  });

  final String name;
  final String url;
  final String defaultModel;
  final String description;
  final AiProtocol protocol;
  final bool local;
}

enum AiProtocol { chat, anthropic }

const aiEndpoints = <AiEndpoint>[
  AiEndpoint(
    name: 'OpenRouter',
    url: 'https://openrouter.ai/api/v1/chat/completions',
    defaultModel: 'openai/gpt-4o-mini',
    description: 'Access eligible routed models with your own API key',
  ),
  AiEndpoint(
    name: 'OpenAI',
    url: 'https://api.openai.com/v1/chat/completions',
    defaultModel: 'gpt-4.1-mini',
    description: 'Requires a funded/authorized OpenAI API account',
  ),
  AiEndpoint(
    name: 'DeepSeek',
    url: 'https://api.deepseek.com/chat/completions',
    defaultModel: 'deepseek-chat',
    description: 'Uses the official DeepSeek compatible API',
  ),
  AiEndpoint(
    name: 'Groq',
    url: 'https://api.groq.com/openai/v1/chat/completions',
    defaultModel: '',
    description: 'Enter an available model ID from your Groq account',
  ),
  AiEndpoint(
    name: 'Google Gemini',
    url: 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
    defaultModel: '',
    description: 'Use your Google AI Studio key and an eligible model ID',
  ),
  AiEndpoint(
    name: 'Anthropic Claude',
    url: 'https://api.anthropic.com/v1/messages',
    defaultModel: '',
    protocol: AiProtocol.anthropic,
    description: 'Use your Anthropic API key and model ID',
  ),
  AiEndpoint(
    name: 'xAI Grok',
    url: 'https://api.x.ai/v1/chat/completions',
    defaultModel: '',
    description: 'Use an eligible Grok chat-completion model (legacy API)',
  ),
  AiEndpoint(
    name: 'Mistral',
    url: 'https://api.mistral.ai/v1/chat/completions',
    defaultModel: '',
    description: 'Use your Mistral API key and model ID',
  ),
  AiEndpoint(
    name: 'Ollama (local)',
    url: 'http://localhost:11434/v1/chat/completions',
    defaultModel: '',
    local: true,
    description: 'Requires a running local Ollama server on this device; desktop only',
  ),
];

class AiSelection {
  const AiSelection(this.endpoint, this.model, this.apiKey);
  final AiEndpoint endpoint;
  final String model, apiKey;
}

class AiCompletion {
  const AiCompletion(this.text, this.provider, {this.fallbackReason});
  final String text, provider;
  final String? fallbackReason;
}

/// Only explicitly selected, fixed endpoints are used. No hidden retries,
/// redirects, persistent credentials or automatic uploads.
class AiChatService {
  AiChatService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const maxPromptChars = 40000;
  static const maxBodyBytes = 2 * 1024 * 1024;
  static const _system = 'You are an Android reverse engineering code analyst. '
      'Explain observed Dalvik instructions, Android XML attributes, API usage '
      'and potential risks with evidence. Separate evidence from inference, '
      'identify uncertainty and do not claim access to files not included.';

  void _validate(AiSelection selection, String prompt) {
    if (!aiEndpoints.contains(selection.endpoint) ||
        selection.model.trim().isEmpty ||
        (!selection.endpoint.local && selection.apiKey.trim().isEmpty) ||
        prompt.trim().isEmpty || prompt.length > maxPromptChars) {
      throw const FormatException('Select a supported provider, model, key if required '
          'and a prompt of at most 40,000 characters');
    }
  }

  Future<AiCompletion> completeWithFallback({
    required AiSelection primary,
    required String prompt,
    AiSelection? fallback,
    bool allowFallback = false,
  }) async {
    _validate(primary, prompt);
    if (allowFallback) {
      if (fallback == null || fallback.endpoint == primary.endpoint) {
        throw const FormatException('Select a different fallback provider');
      }
      _validate(fallback, prompt);
    }
    try {
      final answer = await complete(endpoint: primary.endpoint,
          model: primary.model, apiKey: primary.apiKey, prompt: prompt);
      return AiCompletion(answer, primary.endpoint.name);
    } on HttpException catch (error) {
      if (!allowFallback || fallback == null || !error.retryable) {
        rethrow;
      }
      final answer = await complete(endpoint: fallback.endpoint,
          model: fallback.model, apiKey: fallback.apiKey, prompt: prompt);
      return AiCompletion(answer, fallback.endpoint.name,
          fallbackReason: '${primary.endpoint.name}: HTTP ${error.statusCode}');
    }
  }

  /// Explicit model discovery. No prompt or code is included in this GET.
  /// Pagination is intentionally limited to the first provider response.
  Future<List<String>> listModels(AiEndpoint endpoint, String apiKey) async {
    if (!aiEndpoints.contains(endpoint) ||
        (!endpoint.local && apiKey.trim().isEmpty)) {
      throw const FormatException('Select a supported provider and its API key');
    }
    final url = switch (endpoint.name) {
      'OpenRouter' => 'https://openrouter.ai/api/v1/models',
      'OpenAI' => 'https://api.openai.com/v1/models',
      'DeepSeek' => 'https://api.deepseek.com/models',
      'Groq' => 'https://api.groq.com/openai/v1/models',
      'Google Gemini' => 'https://generativelanguage.googleapis.com/v1beta/openai/models',
      'Anthropic Claude' => 'https://api.anthropic.com/v1/models',
      'xAI Grok' => 'https://api.x.ai/v1/models',
      'Mistral' => 'https://api.mistral.ai/v1/models',
      'Ollama (local)' => 'http://localhost:11434/v1/models',
      _ => throw const FormatException('Model catalog unavailable'),
    };
    final request = http.Request('GET', Uri.parse(url))
      ..followRedirects = false
      ..headers.addAll({
        'Accept': 'application/json',
        if (endpoint.protocol == AiProtocol.anthropic) ...{
          'x-api-key': apiKey.trim(),
          'anthropic-version': '2023-06-01',
        } else if (!endpoint.local)
          'Authorization': 'Bearer ${apiKey.trim()}',
      });
    final response = await _client.send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.listen((_) {}).cancel();
      throw HttpException('Model catalog returned HTTP ${response.statusCode}',
          statusCode: response.statusCode);
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
      if (chunk.length > maxBodyBytes - bytes.length) {
        throw const FormatException('Model catalog exceeded 2 MiB');
      }
      bytes.addAll(chunk);
    }
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map || data['data'] is! List) {
      throw const FormatException('Unsupported model catalog response');
    }
    final ids = <String>{};
    for (final item in (data['data'] as List).take(10000)) {
      if (item is Map && item['id'] is String) {
        final id = (item['id'] as String).trim();
        if (id.isNotEmpty && id.length <= 256) {
          ids.add(id);
        }
      }
      if (ids.length >= 1000) {
        break;
      }
    }
    final sorted = ids.toList()..sort();
    return List.unmodifiable(sorted);
  }

  Future<String> complete({
    required AiEndpoint endpoint,
    required String model,
    required String apiKey,
    required String prompt,
  }) async {
    _validate(AiSelection(endpoint, model, apiKey), prompt);
    final anthropic = endpoint.protocol == AiProtocol.anthropic;
    final request = http.Request('POST', Uri.parse(endpoint.url))
      ..followRedirects = false
      ..headers.addAll({
        'Content-Type': 'application/json',
        if (anthropic) ...{
          'x-api-key': apiKey.trim(),
          'anthropic-version': '2023-06-01',
        } else if (!endpoint.local)
          'Authorization': 'Bearer ${apiKey.trim()}',
      })
      ..body = jsonEncode({
        'model': model.trim(),
        if (anthropic) ...{
          'system': _system,
          'max_tokens': 2048,
        },
        'messages': [
          if (!anthropic) {'role': 'system', 'content': _system},
          {'role': 'user', 'content': prompt.trim()},
        ],
        'stream': false,
      });

    final response = await _client.send(request)
        .timeout(const Duration(seconds: 75));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Do not expose arbitrary server error bodies, which can contain secrets.
      await response.stream.listen((_) {}).cancel();
      final code = response.statusCode;
      throw HttpException(
        code == 401 || code == 403 ? 'API key or model access denied' :
        code == 429 ? 'Rate limit exceeded' : 'Provider returned HTTP $code',
        statusCode: code,
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(const Duration(seconds: 75))) {
      if (chunk.length > maxBodyBytes - bytes.length) {
        throw const FormatException('AI response exceeded 2 MiB');
      }
      bytes.addAll(chunk);
    }
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map) {
      throw const FormatException('Invalid AI response');
    }
    if (anthropic) {
      final blocks = data['content'];
      if (blocks is List) {
        final text = blocks.whereType<Map>()
            .where((block) => block['type'] == 'text')
            .map((block) => block['text']).whereType<String>().join('\n');
        if (text.trim().isNotEmpty) {
          return text;
        }
      }
    } else {
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty && choices.first is Map) {
        final message = (choices.first as Map)['message'];
        final content = message is Map ? message['content'] : null;
        if (content is String && content.trim().isNotEmpty) {
          return content;
        }
      }
    }
    throw const FormatException('Provider returned no text');
  }

  void close() => _client.close();
}

class HttpException implements Exception {
  const HttpException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  bool get retryable => const {429, 502, 503, 504, 529}.contains(statusCode);

  @override
  String toString() => message;
}
