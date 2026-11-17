import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

class WorkspaceListing {
  const WorkspaceListing(this.paths, this.partial);
  final List<String> paths;
  final bool partial;
}

/// Bounded local text workspace. Never writes to the input tree.
class ProjectWorkspaceService {
  const ProjectWorkspaceService._();
  static const maxEntries = 4000;
  static const maxFiles = 1500;
  static const maxTextBytes = 64 * 1024;
  static const maxTabs = 8;

  static bool ignoredPart(String part) => part.isEmpty || part == '.' ||
      part == '..' || part.startsWith('.') ||
      const {'node_modules', 'build', 'obj'}.contains(part.toLowerCase());

  static bool eligible(String path) {
    if (path.isEmpty || path.length > 512 || path.contains('\\') ||
        path.contains(':') || path.contains('\u0000')) {
      return false;
    }
    final parts = path.split('/');
    if (parts.any(ignoredPart)) {
      return false;
    }
    return RegExp(r'\.(java|kt|smali|dart|cs|il|xml|json|txt|md|js|ts|yaml|yml|gradle|kts|properties|csproj|html|css|pro|toml|c|cpp|h|hpp|aidl|sh|bat)$',
        caseSensitive: false).hasMatch(path);
  }

  static Future<WorkspaceListing> list(String root) =>
      Isolate.run(() => listBounded(root));

  /// Traverses only eligible directories, not generated/hidden trees.
  /// Do not follow symlinks; cap work and depth independently.
  static Future<WorkspaceListing> listBounded(String root,
      {int entryLimit = maxEntries, int fileLimit = maxFiles}) async {
    if (entryLimit < 1 || entryLimit > maxEntries ||
        fileLimit < 1 || fileLimit > maxFiles) {
      throw const FormatException('Invalid workspace traversal budget');
    }
    final base = await Directory(root).resolveSymbolicLinks();
    final paths = <String>[];
    final pending = <(Directory, int)>[(Directory(base), 0)];
    var visited = 0;
    var partial = false;
    while (pending.isNotEmpty) {
      final (directory, depth) = pending.removeLast();
      try {
        await for (final entity in directory.list(followLinks: false)) {
          if (++visited > entryLimit || paths.length >= fileLimit) {
            paths.sort();
            return WorkspaceListing(List.unmodifiable(paths), true);
          }
          if (ignoredPart(p.basename(entity.path))) {
            continue;
          }
          final relative = p.relative(entity.path, from: base).replaceAll('\\', '/');
          if (entity is Directory) {
            if (depth < 32 && relative.length <= 512) {
              pending.add((entity, depth + 1));
            } else {
              partial = true;
            }
          } else if (entity is File && eligible(relative)) {
            paths.add(relative);
          }
        }
      } on FileSystemException {
        partial = true;
      }
    }
    paths.sort();
    return WorkspaceListing(List.unmodifiable(paths), partial);
  }

  static Future<String> read(String root, String relative) async {
    if (!eligible(relative)) {
      throw const FormatException('Unsafe or unsupported text path');
    }
    final base = await Directory(root).resolveSymbolicLinks();
    final file = File(p.joinAll([base, ...relative.split('/')]));
    if (await FileSystemEntity.type(file.path, followLinks: false) != FileSystemEntityType.file) {
      throw const FormatException('Not a regular file');
    }
    final resolved = await file.resolveSymbolicLinks();
    if (!p.isWithin(base, resolved) || await file.length() > maxTextBytes) {
      throw const FormatException('File is outside workspace or exceeds 64 KiB');
    }
    final bytes = await file.openRead(0, maxTextBytes + 1)
        .fold<List<int>>([], (all, part) => all..addAll(part));
    if (bytes.length > maxTextBytes || bytes.contains(0)) {
      throw const FormatException('Not bounded UTF-8 text');
    }
    return utf8.decode(bytes);
  }

  static List<int> exportBytes(String text) {
    final bytes = utf8.encode(text);
    if (bytes.length > maxTextBytes || bytes.contains(0)) {
      throw const FormatException('Edited text exceeds 64 KiB or contains NUL');
    }
    return bytes;
  }
}
