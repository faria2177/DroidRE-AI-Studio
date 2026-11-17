import 'dart:convert';

import 'package:droidre_ai_studio/services/ai_chat_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('model discovery sends only provider credential and no prompt', () async {
    final service = AiChatService(client: MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.deepseek.com/models');
      expect(request.headers['Authorization'], 'Bearer discovery-key');
      expect(request.body, isEmpty);
      return http.Response('{"data":[{"id":"z"},{"id":"a"},{"id":"z"},{"id":null}]}', 200);
    }));
    expect(await service.listModels(aiEndpoints[2], 'discovery-key'), ['a', 'z']);
    service.close();
  });

  test('Claude catalog uses native authentication', () async {
    final endpoint = aiEndpoints.singleWhere((e) => e.protocol == AiProtocol.anthropic);
    final service = AiChatService(client: MockClient((request) async {
      expect(request.url.toString(), 'https://api.anthropic.com/v1/models');
      expect(request.headers['x-api-key'], 'claude-key');
      expect(request.headers['anthropic-version'], '2023-06-01');
      expect(request.headers.containsKey('Authorization'), isFalse);
      return http.Response('{"data":[{"id":"claude-example"}],"has_more":true}', 200);
    }));
    expect(await service.listModels(endpoint, 'claude-key'), ['claude-example']);
    service.close();
  });

  test('catalog errors do not trigger fallback or expose raw server body', () async {
    var calls = 0;
    final service = AiChatService(client: MockClient((_) async {
      calls++;
      return http.Response('secret error body', 429);
    }));
    await expectLater(service.listModels(aiEndpoints.first, 'key'),
      throwsA(isA<HttpException>().having((e) => e.statusCode, 'status', 429)));
    expect(calls, 1);
    service.close();
  });

  test('rejects unknown endpoint before catalog request', () async {
    final service = AiChatService(client: MockClient((_) async {
      fail('Unexpected request');
    }));
    await expectLater(service.listModels(const AiEndpoint(
      name: 'Unknown', url: 'https://example.com', defaultModel: ''), 'key'),
      throwsFormatException);
    service.close();
  });

  test('parses an authorized chat completion response', () async {
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(jsonDecode(request.body)['model'], 'demo-model');
      return http.Response(jsonEncode({
        'choices': [
          {'message': {'role': 'assistant', 'content': 'Analysis complete'}}
        ],
      }), 200);
    });
    final service = AiChatService(client: client);
    final answer = await service.complete(
      endpoint: aiEndpoints.first,
      model: 'demo-model',
      apiKey: 'test-token',
      prompt: 'Explain this manifest',
    );
    expect(answer, 'Analysis complete');
    service.close();
  });

  test('uses native Claude API and collects text blocks', () async {
    final endpoint = aiEndpoints.singleWhere((e) => e.name == 'Anthropic Claude');
    final service = AiChatService(client: MockClient((request) async {
      expect(request.headers['x-api-key'], 'claude-key');
      expect(request.headers['anthropic-version'], '2023-06-01');
      expect(request.headers.containsKey('Authorization'), isFalse);
      final body = jsonDecode(request.body) as Map;
      expect(body['max_tokens'], 2048);
      expect(body['system'], isNotEmpty);
      return http.Response(jsonEncode({'content': [
        {'type': 'thinking', 'thinking': 'not output'},
        {'type': 'text', 'text': 'One'},
        {'type': 'text', 'text': 'Two'},
      ]}), 200);
    }));
    expect(await service.complete(endpoint: endpoint, model: 'test',
      apiKey: 'claude-key', prompt: 'hello'), 'One\nTwo');
    service.close();
  });

  test('uses fallback once with a separate credential on rate limit', () async {
    var calls = 0;
    final service = AiChatService(client: MockClient((request) async {
      calls++;
      if (calls == 1) {
        expect(request.headers['Authorization'], 'Bearer first-key');
        return http.Response('', 429);
      }
      expect(request.url.host, 'api.groq.com');
      expect(request.headers['Authorization'], 'Bearer second-key');
      return http.Response('{"choices":[{"message":{"content":"fallback"}}]}', 200);
    }));
    final result = await service.completeWithFallback(
      primary: AiSelection(aiEndpoints.first, 'one', 'first-key'),
      fallback: AiSelection(aiEndpoints[3], 'two', 'second-key'),
      prompt: 'hello', allowFallback: true,
    );
    expect(result.provider, 'Groq');
    expect(result.fallbackReason, contains('429'));
    expect(calls, 2);
    service.close();
  });

  test('does not fallback on auth denial or without consent', () async {
    for (final (code, consent) in [(401, true), (429, false)]) {
      var calls = 0;
      final service = AiChatService(client: MockClient((_) async {
        calls++;
        return http.Response('', code);
      }));
      await expectLater(service.completeWithFallback(
        primary: AiSelection(aiEndpoints.first, 'one', 'key'),
        fallback: AiSelection(aiEndpoints[3], 'two', 'other'),
        prompt: 'hello', allowFallback: consent,
      ), throwsA(isA<HttpException>()));
      expect(calls, 1);
      service.close();
    }
  });

  test('Ollama uses loopback and does not send an API key', () async {
    final endpoint = aiEndpoints.singleWhere((e) => e.local);
    final service = AiChatService(client: MockClient((request) async {
      expect(request.url.host, 'localhost');
      expect(request.url.port, 11434);
      expect(request.headers.containsKey('Authorization'), isFalse);
      return http.Response('{"choices":[{"message":{"content":"local"}}]}', 200);
    }));
    expect(await service.complete(endpoint: endpoint, model: 'local-model',
      apiKey: '', prompt: 'hello'), 'local');
    service.close();
  });

  test('reports rate limiting without automatic hidden provider switch', () async {
    final service = AiChatService(
      client: MockClient((_) async => http.Response('', 429)),
    );
    expect(
      () => service.complete(
        endpoint: aiEndpoints.first,
        model: 'model',
        apiKey: 'test-key',
        prompt: 'hello',
      ),
      throwsA(isA<HttpException>()),
    );
    service.close();
  });
}
