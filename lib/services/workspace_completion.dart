import 'project_symbol_index.dart';

/// Explicit, local, current-file declaration suggestions (not semantic LSP).
class WorkspaceCompletion {
  const WorkspaceCompletion._();
  static (int, int, List<String>) suggestions(String text, int cursor, String path) {
    if (cursor < 0 || cursor > text.length || text.length > 65536) {
      return (cursor, cursor, []);
    }
    var start = cursor;
    final identifier = RegExp(r'[A-Za-z0-9_$]');
    while (start > 0 && cursor - start < 128 &&
        identifier.hasMatch(text[start - 1])) {
      start--;
    }
    final prefix = text.substring(start, cursor);
    if (!RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]{0,127}$').hasMatch(prefix)) {
      return (start, cursor, []);
    }
    var end = cursor;
    while (end < text.length && end - start < 128 && identifier.hasMatch(text[end])) {
      end++;
    }
    final names = ProjectSymbolIndex.extract(path, text).map((s) => s.name)
      .where((name) => name != prefix && name.startsWith(prefix) &&
        RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]{0,127}$').hasMatch(name))
      .toSet().toList()..sort();
    return (start, end, names.take(30).toList());
  }
}
