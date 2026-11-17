import 'dart:io';

import 'package:droidre_ai_studio/services/project_context_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches case insensitive literal and preserves relative line references', () {
    final hits = ProjectContextSearch.matchText('sources/Main.java',
        'first\nsecond\nTokenManager.load()\nfourth\nlast', 'tokenmanager');
    expect(hits.single.firstLine, 1);
    expect(hits.single.lastLine, 5);
    expect(hits.single.text, contains('3: TokenManager.load()'));
  });

  test('draft includes only selected evidence and untrusted-data guard', () {
    final prompt = ProjectContextSearch.draft('Explain',
      [const CodeEvidence('a.java', 3, 3, '3: selected')]);
    expect(prompt, contains('a.java'));
    expect(prompt, contains('untrusted data'));
    expect(prompt, contains('"firstLine":3'));
    expect(() => ProjectContextSearch.draft('Explain', []), throwsFormatException);
  });

  test('local search skips oversized and non-text files', () async {
    final root = await Directory.systemTemp.createTemp('droidre_context_');
    try {
      await File('${root.path}/a.java').writeAsString('hello needle');
      await File('${root.path}/b.dex').writeAsString('needle');
      await File('${root.path}/c.txt').writeAsString('needle${List.filled(ProjectContextSearch.maxFileBytes, 'x').join()}');
      final report = await ProjectContextSearch.local(root.path, 'needle');
      expect(report.matches.single.path, 'a.java');
      expect(report.filesRead, 1);
      expect(report.partial, true);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('rejects unsafe paths and empty queries', () {
    expect(ProjectContextSearch.eligible('../a.java'), false);
    expect(ProjectContextSearch.eligible('.git/config.txt'), false);
    expect(ProjectContextSearch.eligible('source/main.dart'), true);
    expect(ProjectContextSearch.eligible('sources/Main.cs'), true);
    expect(ProjectContextSearch.eligible('sources/project.csproj'), true);
    expect(() => ProjectContextSearch.matchText('a.java', 'code', ''), throwsFormatException);
  });
}
