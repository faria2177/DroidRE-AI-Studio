import 'dart:io';

import 'package:droidre_ai_studio/services/workspace_navigation_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persists per-workspace navigation, bounds paths and supports deletion', () async {
    final root = await Directory.systemTemp.createTemp('navigation_store_');
    try {
      final store = WorkspaceNavigationStore(root);
      await store.save('local:one', const WorkspaceNavigation(
        [('src/Main.java', 8), ('../secret.java', 1), ('src/Main.java', 8)],
        [('src/Main.java', 2)]));
      final reopened = WorkspaceNavigationStore(root);
      final state = await reopened.load('local:one');
      expect(state.bookmarks, [('src/Main.java', 8)]);
      expect(state.history, [('src/Main.java', 2)]);
      expect((await reopened.load('local:two')).bookmarks, isEmpty);
      await reopened.save('local:one', const WorkspaceNavigation(
        [('src/Other.cs', 4)], []));
      expect((await reopened.load('local:one')).bookmarks, [('src/Other.cs', 4)]);
      await reopened.clear('local:one');
      expect((await store.load('local:one')).history, isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
