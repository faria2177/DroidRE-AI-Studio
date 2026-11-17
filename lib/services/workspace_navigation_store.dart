import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'project_workspace_service.dart';

typedef WorkspaceLocation = (String, int);

class WorkspaceNavigation {
  const WorkspaceNavigation(this.bookmarks, this.history);
  final List<WorkspaceLocation> bookmarks, history;
}

class WorkspaceNavigationStore {
  const WorkspaceNavigationStore(this.directory);
  final Directory directory;
  static const maxLocations = 100;
  static const maxBytes = 768 * 1024;

  static Future<WorkspaceNavigationStore> appLocal() async {
    final support = await getApplicationSupportDirectory();
    return WorkspaceNavigationStore(Directory(p.join(support.path, 'workspace-navigation')));
  }

  String _key(String identity) {
    if (identity.isEmpty || identity.length > 8192) {
      throw const FormatException('Invalid workspace identity');
    }
    return sha256.convert(utf8.encode(identity)).toString();
  }

  List<WorkspaceLocation> _validated(Iterable<WorkspaceLocation> locations) {
    return locations.where((item) =>
        ProjectWorkspaceService.eligible(item.$1) &&
        item.$2 >= 1 && item.$2 <= ProjectWorkspaceService.maxTextBytes + 1)
        .toSet().take(maxLocations).toList();
  }

  List<WorkspaceLocation> _readLocations(Object? value) {
    if (value is! List) {
      return [];
    }
    final result = <WorkspaceLocation>[];
    for (final entry in value.take(maxLocations)) {
      if (entry is List && entry.length == 2 && entry[0] is String && entry[1] is int) {
        result.add((entry[0] as String, entry[1] as int));
      }
    }
    return _validated(result);
  }

  Future<WorkspaceNavigation> load(String identity) async {
    final file = File(p.join(directory.path, '${_key(identity)}.json'));
    if (!await file.exists()) {
      return const WorkspaceNavigation([], []);
    }
    if (await file.length() > maxBytes) {
      throw const FormatException('Workspace navigation data exceeds limit');
    }
    final bytes = await file.openRead(0, maxBytes + 1)
        .fold<List<int>>([], (all, part) => all..addAll(part));
    if (bytes.length > maxBytes) {
      throw const FormatException('Workspace navigation data exceeds limit');
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map || value['schema'] != 1) {
      throw const FormatException('Unsupported navigation data');
    }
    return WorkspaceNavigation(_readLocations(value['bookmarks']),
      _readLocations(value['history']));
  }

  Future<void> save(String identity, WorkspaceNavigation navigation) async {
    final key = _key(identity);
    await directory.create(recursive: true);
    final bytes = utf8.encode(jsonEncode({
      'schema': 1,
      'bookmarks': _validated(navigation.bookmarks).map((item) => [item.$1, item.$2]).toList(),
      'history': _validated(navigation.history).map((item) => [item.$1, item.$2]).toList(),
    }));
    if (bytes.length > maxBytes) {
      throw const FormatException('Workspace navigation exceeds limit');
    }
    final temp = await directory.createTemp('stage-');
    try {
      final file = File(p.join(temp.path, 'navigation.json'));
      await file.writeAsBytes(bytes, flush: true);
      await file.rename(p.join(directory.path, '$key.json'));
    } finally {
      await temp.delete(recursive: true);
    }
  }

  Future<void> clear(String identity) async {
    final file = File(p.join(directory.path, '${_key(identity)}.json'));
    if (await file.exists()) {
      await file.delete();
    }
  }
}
