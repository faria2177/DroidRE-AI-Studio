import 'package:droidre_ai_studio/services/workspace_draft_diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shows insertion and removal without changing source', () {
    expect(WorkspaceDraftDiff.compare('a\nb\nc', 'a\nx\nc'), contains('- b\n+ x'));
    expect(WorkspaceDraftDiff.compare('same', 'same'), 'No changes');
    expect(() => WorkspaceDraftDiff.compare(List.filled(65537, 'x').join(), ''), throwsFormatException);
  });
}
