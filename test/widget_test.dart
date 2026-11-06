import 'package:droidre_ai_studio/screens/studio_screens.dart';
import 'package:droidre_ai_studio/services/studio_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home shows the real APK import action', (tester) async {
    final controller = StudioController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            controller: controller,
            onImport: () {},
            openProjects: () {},
            openInspector: () {},
          ),
        ),
      ),
    );

    expect(find.text('Import an APK or bundle'), findsOneWidget);
    expect(find.text('No projects yet'), findsOneWidget);
    controller.dispose();
  });
}
