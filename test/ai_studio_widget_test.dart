import 'package:droidre_ai_studio/screens/studio_screens.dart';
import 'package:droidre_ai_studio/services/ai_chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Keep widget tests independent of HTTP stream scheduling in fake time.
/// Actual provider requests and response parsing are tested separately.
class _RecordingAiService extends AiChatService {
  final prompts = <String>[];
  final keys = <String>[];

  @override
  Future<String> complete({
    required AiEndpoint endpoint,
    required String model,
    required String apiKey,
    required String prompt,
  }) {
    prompts.add(prompt);
    keys.add(apiKey);
    return Future.value('Provider response');
  }
}

void main() {
  testWidgets('connection check sends no project code and reviewed Send sends it', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _RecordingAiService();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      AiStudioScreen(initialPrompt: 'private source sample', chatService: service))));
    final scroll = find.byType(Scrollable).first;
    final keyField = find.widgetWithText(TextField, 'API key (session only)');
    await tester.scrollUntilVisible(keyField, 150, scrollable: scroll);
    await tester.enterText(keyField, 'test-key');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final connection = find.text('Test connection (sends OK prompt only; may use quota)');
    await tester.scrollUntilVisible(connection, 120, scrollable: scroll);
    await tester.tap(connection);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(service.prompts, ['Reply with OK only.']);
    expect(service.keys, ['test-key']);
    expect(find.textContaining('Connection test succeeded'), findsOneWidget);
    final consent = find.text('I reviewed the extracted code and agree to send this text to the selected AI provider');
    await tester.scrollUntilVisible(consent, 150, scrollable: scroll);
    await tester.tap(consent);
    await tester.pump();
    final send = find.text('Send to selected provider');
    await tester.scrollUntilVisible(send, 150, scrollable: scroll);
    await tester.tap(send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(service.prompts, ['Reply with OK only.', 'private source sample']);
    expect(service.keys, ['test-key', 'test-key']);
    final output = find.text('Provider: OpenRouter\n\nProvider response');
    await tester.scrollUntilVisible(output, 120, scrollable: scroll);
    expect(output, findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
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
