import 'dart:convert';

import 'package:droidre_ai_studio/services/ai_chat_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
