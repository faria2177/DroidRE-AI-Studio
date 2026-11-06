import 'dart:convert';

import 'package:http/http.dart' as http;

class AiEndpoint {
  const AiEndpoint({
    required this.name,
    required this.url,
    required this.defaultModel,
    this.description = '',
  });

  final String name;
  final String url;
  final String defaultModel;
  final String description;
}

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
];

/// Calls only the endpoint explicitly selected by the user.
/// The API key is held in memory and is never persisted or logged.
class AiChatService {
  AiChatService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<String> complete({
    required AiEndpoint endpoint,
    required String model,
    required String apiKey,
    required String prompt,
  }) async {
    if (apiKey.trim().isEmpty || model.trim().isEmpty || prompt.trim().isEmpty) {
      throw const FormatException('API key, model and prompt are required');
    }
    final response = await _client
        .post(
          Uri.parse(endpoint.url),
          headers: {
            'Authorization': 'Bearer ${apiKey.trim()}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model.trim(),
            'messages': [
              {
                'role': 'system',
                'content':
                    'You are an Android reverse engineering code analyst. '
                    'Explain observed Dalvik instructions, Android XML attributes, '
                    'API usage and potential risks with short evidence-based reasoning. '
                    'Separate evidence from inference, identify uncertainty, and '
                    'do not claim access to files not explicitly included in the prompt.',
              },
              {'role': 'user', 'content': prompt.trim()},
            ],
            'stream': false,
          }),
        )
        .timeout(const Duration(seconds: 75));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const HttpException('API key or model access was denied');
    }
    if (response.statusCode == 429) {
      throw const HttpException('Rate limit exceeded; retry later');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Provider returned HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data is! Map) throw const FormatException('Invalid AI response');
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const FormatException('No AI output returned');
    }
    final message = (choices.first as Map)['message'];
    final content = message is Map ? message['content'] : null;
    if (content is String && content.isNotEmpty) return content;
    throw const FormatException('Provider returned no text');
  }

  void close() => _client.close();
}

class HttpException implements Exception {
  const HttpException(this.message);
  final String message;

  @override
  String toString() => message;
}
