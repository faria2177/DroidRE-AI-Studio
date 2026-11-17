import 'package:droidre_ai_studio/services/agent_evidence_verifier.dart';
import 'package:droidre_ai_studio/services/analysis_agent.dart';
import 'package:droidre_ai_studio/services/project_context_search.dart';
import 'package:droidre_ai_studio/services/workspace_completion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('evidence verifier distinguishes changed and matching source', () async {
    const item = AgentEvidence('E1', CodeEvidence('Main.java', 1, 2, '1: class Main {\n2: }'));
    expect(AgentEvidenceVerifier.verify(item, 'class Main {\n}'), 'exact lines match');
    expect(AgentEvidenceVerifier.verify(item, 'class Other {\n}'), 'changed');
    expect(await AgentEvidenceVerifier.check([item], (_) async => 'class Main {\n}'),
      contains('exact lines match'));
  });
  test('local declaration prefix returns bounded replacement range', () {
    const text = 'class Example {}\nExa';
    final (start, end, names) = WorkspaceCompletion.suggestions(text, text.length, 'Main.java');
    expect(names, ['Example']);
    expect(text.replaceRange(start, end, names.single), 'class Example {}\nExample');
  });
}
