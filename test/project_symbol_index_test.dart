import 'package:droidre_ai_studio/services/project_symbol_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('declaration hints preserve line references', () {
    final result = ProjectSymbolIndex.extract('Main.java',
      '// class Fake\npublic class Main {\npublic void start() {\n}');
    expect(result.map((s) => s.name), ['Main', 'start']);
    expect(result.map((s) => s.line), [2, 3]);
  });
  test('smali and named function hints', () {
    expect(ProjectSymbolIndex.extract('a.smali', '.method public run()V').single.name, 'run');
    expect(ProjectSymbolIndex.extract('a.kt', 'fun demo() {}').single.name, 'demo');
    expect(ProjectSymbolIndex.extract('a.js', 'function demo() {}', limit: 0), isEmpty);
  });
}
