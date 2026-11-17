import 'package:droidre_ai_studio/services/external_tool_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('version checks have fixed argument lists', () {
    expect(ExternalToolManager.versionArgs(ToolKind.java), ['-version']);
    expect(ExternalToolManager.versionArgs(ToolKind.adb), ['version']);
    expect(ExternalToolManager.versionArgs(ToolKind.llvm), ['--version']);
    expect(() => ExternalToolManager.versionArgs(ToolKind.ghidra), throwsFormatException);
  });
}
