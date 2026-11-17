import 'package:droidre_ai_studio/models/apk_report.dart';
import 'package:droidre_ai_studio/services/ai_project_brief.dart';
import 'package:droidre_ai_studio/services/ai_session_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active recovered project adds actual text with path and line references', () async {
    final report = ApkReport.fromJson({
      'id': 'one', 'fileName': 'sample.apk', 'manifest': {'packageName':'com.demo'},
      'recoveredFileCount': 470, 'recoveryPartial': true,
    });
    final draft = await AiProjectBrief.build(report, 'Explain MainActivity',
      ['src/MainActivity.java', '../secret.txt'], (path) async {
        expect(path, 'src/MainActivity.java');
        return 'class MainActivity {\nvoid scan() {}\n}';
      });
    expect(draft, contains('com.demo'));
    expect(draft, contains('"generatedFileCount":470'));
    expect(draft, contains('src/MainActivity.java'));
    expect(draft, contains('2: void scan() {}'));
    expect(draft, isNot(contains('../secret.txt')));
    expect(draft.length, lessThanOrEqualTo(32000));
  });
  test('history is bounded, contains raw turns, and can be cleared', () {
    final history = AiSessionContext();
    history.add('source evidence', 'initial finding');
    final follow = history.followUp('summarize findings');
    expect(follow, contains('source evidence'));
    expect(follow, contains('initial finding'));
    expect(follow, contains('summarize findings'));
    for (var i = 0; i < 4; i++) {
      history.add('question $i', 'answer $i');
    }
    expect(history.count, 3);
    expect(history.followUp('next'), isNot(contains('initial finding')));
    history.clear();
    expect(history.followUp('new project'), 'new project');
  });
}
