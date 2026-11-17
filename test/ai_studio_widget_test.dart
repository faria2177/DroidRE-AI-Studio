import 'package:droidre_ai_studio/screens/studio_screens.dart';
import 'package:droidre_ai_studio/services/ai_chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
