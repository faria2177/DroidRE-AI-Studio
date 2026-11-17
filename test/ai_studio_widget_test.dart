import 'package:droidre_ai_studio/screens/studio_screens.dart';
import 'package:droidre_ai_studio/services/ai_chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('connection check sends no project code and reviewed Send sends it', (tester) async {
    final prompts = <String>[];
    final service = AiChatService(client: MockClient((request) async {
      final body = request.body;
      expect(request.headers['Authorization'], 'Bearer test-key');
      prompts.add(body);
      return http.Response('{"choices":[{"message":{"content":"Provider response"}}]}', 200);
    }));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      AiStudioScreen(initialPrompt: 'private source sample', chatService: service))));
    final scroll = find.byType(Scrollable).first;
    final keyField = find.widgetWithText(TextField, 'API key (session only)');
    await tester.scrollUntilVisible(keyField, 150, scrollable: scroll);
    await tester.enterText(keyField, 'test-key');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final connection = find.text('Test connection (sends OK prompt only; may use quota)');
    await tester.scrollUntilVisible(connection, 120, scrollable: scroll);
    await tester.tap(connection);
    await tester.pumpAndSettle();
    expect(prompts.length, 1);
    expect(prompts.single, contains('Reply with OK only.'));
    expect(prompts.single, isNot(contains('private source sample')));
    final consent = find.text('I reviewed the extracted code and agree to send this text to the selected AI provider');
    await tester.scrollUntilVisible(consent, 150, scrollable: scroll);
    await tester.tap(consent);
    await tester.pumpAndSettle();
    final send = find.text('Send to selected provider');
    await tester.scrollUntilVisible(send, 150, scrollable: scroll);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(prompts.length, 2);
    expect(prompts.last, contains('private source sample'));
    final output = find.textContaining('Provider response');
    await tester.scrollUntilVisible(output.last, 120, scrollable: scroll);
    expect(output, findsWidgets);
  });
  testWidgets('new inspector draft retains key/model and requires renewed consent', (tester) async {
    final service = AiChatService(client: MockClient((_) async =>
      http.Response('{"choices":[{"message":{"content":"OK"}}]}', 200)));
    Widget screen(String draft, int revision) => MaterialApp(home: Scaffold(
      body: AiStudioScreen(initialPrompt: draft, draftRevision: revision, chatService: service)));
    await tester.pumpWidget(screen('first code', 1));
    final keyField = find.widgetWithText(TextField, 'API key (session only)');
    await tester.scrollUntilVisible(keyField, 150, scrollable: find.byType(Scrollable).first);
    await tester.enterText(keyField, 'session-test-key');
    await tester.pump();
    await tester.pumpWidget(screen('second code', 2));
    await tester.pump();
    expect(tester.widget<TextField>(keyField).controller!.text, 'session-test-key');
    final prompt = find.widgetWithText(TextField, 'Ask about Android code');
    await tester.scrollUntilVisible(prompt, 150, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<TextField>(prompt).controller!.text, 'second code');
    final send = find.ancestor(of: find.text('Send to selected provider'), matching: find.byWidgetPredicate((w) => w is FilledButton));
    await tester.scrollUntilVisible(send, 150, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
  });
}
