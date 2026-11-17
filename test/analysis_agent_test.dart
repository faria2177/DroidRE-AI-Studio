import 'package:droidre_ai_studio/services/analysis_agent.dart';
import 'package:droidre_ai_studio/services/project_context_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plan accepts only bounded literal query data', () {
    expect(AnalysisAgent.parsePlan('{"queries":["MainActivity","onCreate"]}'),
      ['MainActivity', 'onCreate']);
    expect(() => AnalysisAgent.parsePlan('{"queries":["../secret"]}'), throwsFormatException);
    expect(() => AnalysisAgent.parsePlan('{"queries":["a","A"]}'), throwsFormatException);
    expect(() => AnalysisAgent.parsePlan('{"queries":["a"],"command":"run"}'), throwsFormatException);
  });

  test('collection deduplicates excerpts and retains stable IDs', () async {
    final called = <String>[];
    final items = await AnalysisAgent.collect(['first', 'second'], (term) async {
      called.add(term);
      return const CodeSearchResult([
        CodeEvidence('Main.java', 1, 2, 'sample'),
        CodeEvidence('../bad.java', 1, 1, 'bad'),
      ], 1, true);
    });
    expect(called, ['first', 'second']);
    expect(items.single.id, 'E1');
    expect(items.single.code.path, 'Main.java');
  });

  test('report refuses citations outside reviewed set', () {
    const evidence = [AgentEvidence('E1', CodeEvidence('Main.java', 1, 2, 'code'))];
    final prompt = AnalysisAgent.reportPrompt('Explain code', evidence);
    expect(prompt, contains('"id":"E1"'));
    final report = AnalysisAgent.parseReport(
      '{"summary":"Summary","findings":[{"observation":"Observed","inference":"Possible","evidenceIds":["E1"]}],"unknowns":["Not known"]}',
      evidence);
    expect(AnalysisAgent.render(report, 'Question', 'test', evidence), contains('E1: Main.java:1–2'));
    expect(() => AnalysisAgent.parseReport(
      '{"summary":"Summary","findings":[{"observation":"Observed","inference":"Possible","evidenceIds":["E2"]}],"unknowns":[]}',
      evidence), throwsFormatException);
  });

  test('cancellation prevents subsequent research queries', () async {
    var stop = false;
    var count = 0;
    await expectLater(AnalysisAgent.collect(['first','second'], (term) async {
      count++;
      stop = true;
      return const CodeSearchResult([], 0, true);
    }, cancelled: () => stop), throwsFormatException);
    expect(count, 1);
  });
}
