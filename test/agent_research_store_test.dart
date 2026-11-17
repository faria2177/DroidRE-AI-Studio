import 'dart:io';
import 'package:droidre_ai_studio/services/agent_research_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('explicit saved plan is workspace scoped and clearable', () async {
    final root = await Directory.systemTemp.createTemp('agent-plan-');
    try {
      final store = AgentResearchStore(root);
      await store.save('workspace-a', const ResearchPlan('How does scanning work?', ['scan', 'camera']));
      final plan = await store.load('workspace-a');
      expect(plan?.question, 'How does scanning work?');
      expect(plan?.queries, ['scan', 'camera']);
      expect(await store.load('workspace-b'), isNull);
      await store.clear('workspace-a');
      expect(await store.load('workspace-a'), isNull);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
