import 'dart:convert';

class WorkspaceDraftDiff {
  const WorkspaceDraftDiff._();
  static String compare(String before, String after) {
    if (before.length > 65536 || after.length > 65536) {
      throw const FormatException('Draft comparison exceeds 64 Ki characters');
    }
    if (before == after) {
      return 'No changes';
    }
    final a = const LineSplitter().convert(before);
    final b = const LineSplitter().convert(after);
    var prefix = 0;
    while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < a.length - prefix && suffix < b.length - prefix &&
        a[a.length - 1 - suffix] == b[b.length - 1 - suffix]) {
      suffix++;
    }
    final old = a.sublist(prefix, a.length - suffix);
    final next = b.sublist(prefix, b.length - suffix);
    final out = StringBuffer('Changed line region starts at ${prefix + 1}\n');
    if (old.length > 200 || next.length > 200) {
      out.writeln('Large changed region; first 100 removed/added lines only.');
      for (final line in old.take(100)) {
        out.writeln('- $line');
      }
      for (final line in next.take(100)) {
        out.writeln('+ $line');
      }
    } else {
      final n = old.length, m = next.length;
      final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
      for (var i = n - 1; i >= 0; i--) {
        for (var j = m - 1; j >= 0; j--) {
          lcs[i][j] = old[i] == next[j] ? lcs[i + 1][j + 1] + 1 :
              (lcs[i + 1][j] > lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
        }
      }
      var i = 0, j = 0;
      while (i < n || j < m) {
        if (i < n && j < m && old[i] == next[j]) {
          out.writeln('  ${old[i]}');
          i++; j++;
        } else if (i < n && (j == m || lcs[i + 1][j] >= lcs[i][j + 1])) {
          out.writeln('- ${old[i++]}');
        } else {
          out.writeln('+ ${next[j++]}');
        }
      }
    }
    if (old.isEmpty && next.isEmpty) {
      out.writeln('Line-ending or trailing-newline change.');
    }
    final text = out.toString();
    return text.length > 24000 ? '${text.substring(0, 24000)}\n(output clipped)' : text;
  }
}
