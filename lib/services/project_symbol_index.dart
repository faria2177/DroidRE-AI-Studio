import 'dart:convert';

import 'project_workspace_service.dart';
import 'saf_source_recovery_service.dart';

class ProjectSymbol {
  const ProjectSymbol(this.path, this.name, this.kind, this.line);
  final String path, name, kind;
  final int line;
}

class ProjectSymbolIndex {
  const ProjectSymbolIndex._();
  static final _type = RegExp(r'\b(class|interface|enum|struct|record|object)\s+([A-Za-z_$][\w$]*)');
  static final _function = RegExp(r'\b(fun|function|def)\s+([A-Za-z_$][\w$]*)\s*\(');
  static final _method = RegExp(r'^\s*(?:\.method\s+|(?:(?:public|private|protected|internal|static|final|virtual|override|async)\s+)+)[^()]*?([A-Za-z_$<>][\w$<>]*)\s*\(');

  static List<ProjectSymbol> extract(String path, String text, {int limit = 3000}) {
    if (limit < 0 || limit > 3000 || text.length > 65536) {
      throw const FormatException('Symbol extraction bounds exceeded');
    }
    final lines = const LineSplitter().convert(text);
    final result = <ProjectSymbol>[];
    for (var i = 0; i < lines.length && result.length < limit; i++) {
      final line = lines[i].trimLeft();
      if (line.startsWith('//') || line.startsWith('*') || line.startsWith('#')) {
        continue;
      }
      final type = _type.firstMatch(line);
      final fun = _function.firstMatch(line);
      final method = _method.firstMatch(line);
      if (type != null) {
        result.add(ProjectSymbol(path, type.group(2)!, type.group(1)!, i + 1));
      } else if (fun != null) {
        result.add(ProjectSymbol(path, fun.group(2)!, 'function', i + 1));
      } else if (method != null) {
        result.add(ProjectSymbol(path, method.group(1)!, 'method', i + 1));
      }
    }
    return result;
  }

  static Future<(List<ProjectSymbol>, bool)> scan(List<String> paths,
      {String? root, String? uri}) async {
    final result = <ProjectSymbol>[];
    var used = 0;
    var partial = uri != null;
    for (final path in paths.take(250)) {
      if (result.length >= 3000 || used >= 2097152) {
        partial = true;
        break;
      }
      try {
        final text = uri != null
            ? await SafSourceRecoveryService.readFile(uri, path)
            : await ProjectWorkspaceService.read(root!, path);
        final size = utf8.encode(text).length;
        if (size > 65536 || size > 2097152 - used ||
            text.startsWith('This file is larger')) {
          partial = true;
          continue;
        }
        used += size;
        result.addAll(extract(path, text, limit: 3000 - result.length));
      } catch (_) {
        partial = true;
      }
    }
    return (result, partial || paths.length > 250 || result.length == 3000);
  }
}
