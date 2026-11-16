import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

import 'elf_dependency_inspector.dart';

enum NativeDependencyStatus {
  packaged,
  notPackaged,
  packagedNotScanned,
  ambiguous,
}

@immutable
class NativeDependencyEdge {
  const NativeDependencyEdge({
    required this.fromPath,
    required this.neededName,
    required this.status,
    this.toPath,
    this.candidates = const [],
  });

  final String fromPath;
  final String neededName;
  final NativeDependencyStatus status;
  final String? toPath;
  final List<String> candidates;
}

@immutable
class NativeDependencyNode {
  const NativeDependencyNode({
    required this.path,
    this.soname,
    required this.inspected,
    this.warning,
  });

  final String path;
  final String? soname;
  final bool inspected;
  final String? warning;

  String get filename => path.substring(path.lastIndexOf('/') + 1);
}

@immutable
class NativeDependencyGraph {
  const NativeDependencyGraph({
    required this.rootPath,
    required this.abiDirectory,
    required this.nodes,
    required this.edges,
    required this.cycles,
    required this.warnings,
    required this.truncated,
  });

  final String rootPath;
  final String abiDirectory;
  final List<NativeDependencyNode> nodes;
  final List<NativeDependencyEdge> edges;
  final List<String> cycles;
  final List<String> warnings;
  final bool truncated;
}

/// Bounded, read-only graph of DT_NEEDED declarations in one APK ABI folder.
/// An APK archive is decoded once, then one native member at a time.
/// Unpackaged dependencies could be Android system libraries; absence from
/// the archive must not be reported as a missing runtime dependency.
class NativeDependencyGraphInspector {
  const NativeDependencyGraphInspector._();

  static const maxLibraries = 64;
  static const maxEntryBytes = 48 * 1024 * 1024;
  static const maxTotalBytes = 128 * 1024 * 1024;
  static const maxZipEntries = 200000;

  static Future<NativeDependencyGraph> inspectEntry(
    String apkPath,
    String selectedPath,
    List<String> apkLibraries,
  ) => Isolate.run(() {
    if (!selectedPath.contains('/') || selectedPath.startsWith('/') ||
        selectedPath.replaceAll('\\', '/').split('/').contains('..')) {
      throw const FormatException('Invalid native library path');
    }
    final directory = selectedPath.contains('/')
        ? selectedPath.substring(0, selectedPath.lastIndexOf('/'))
        : '';
    final eligible = apkLibraries.where((path) {
      return path != selectedPath &&
          path.endsWith('.so') &&
          path.startsWith('$directory/') &&
          path.substring(0, path.lastIndexOf('/')) == directory;
    }).toSet().toList()..sort();

    final paths = <String>[selectedPath, ...eligible];
    final warnings = <String>[];
    final truncated = paths.length > maxLibraries;
    final selected = paths.take(maxLibraries).toList();
    if (truncated) {
      warnings.add('Only first $maxLibraries ABI-matched libraries inspected; '
          'results are partial');
    }
    final reports = <String, ElfDependencyReport>{};
    final failures = <String, String>{};
    var bytesRead = 0;

    final stream = InputFileStream(apkPath);
    try {
      final archive = ZipDecoder().decodeStream(stream, throwOnError: true);
      if (archive.files.length > maxZipEntries) {
        throw const FormatException('APK has too many ZIP entries');
      }
      final byName = <String, ArchiveFile>{};
      final duplicates = <String>{};
      for (final file in archive.files) {
        if (!selected.contains(file.name)) continue;
        if (byName.containsKey(file.name)) {
          duplicates.add(file.name);
        } else {
          byName[file.name] = file;
        }
      }
      for (final path in selected) {
        final file = byName[path];
        if (duplicates.contains(path)) {
          failures[path] = 'Duplicate APK entry';
          continue;
        }
        if (file == null || !file.isFile || file.isSymbolicLink) {
          failures[path] = 'No regular APK library entry';
          continue;
        }
        if (file.size > maxEntryBytes ||
            file.size > maxTotalBytes - bytesRead) {
          failures[path] = 'Per-library or total scan byte limit';
          continue;
        }
        try {
          final data = file.readBytes();
          if (data == null || data.length > maxEntryBytes ||
              data.length > maxTotalBytes - bytesRead) {
            failures[path] = 'Unable to decode within byte limit';
            continue;
          }
          bytesRead += data.length;
          reports[path] = ElfDependencyInspector.inspectBytes(
            Uint8List.fromList(data),
          );
        } on FormatException catch (error) {
          failures[path] = error.message;
        }
      }
    } finally {
      stream.close();
    }

    return buildGraph(
      rootPath: selectedPath,
      abiDirectory: directory,
      paths: selected,
      knownPaths: paths,
      reports: reports,
      failures: failures,
      additionalWarnings: warnings,
      truncated: truncated,
    );
  });

  /// Testable graph constructor. Only same-ABI library paths are passed in.
  /// Resolve SONAME aliases and filename matches conservatively: multiple
  /// candidates are ambiguous, never silently chosen.
  static NativeDependencyGraph buildGraph({
    required String rootPath,
    required String abiDirectory,
    required List<String> paths,
    required Map<String, ElfDependencyReport> reports,
    List<String>? knownPaths,
    Map<String, String> failures = const {},
    List<String> additionalWarnings = const [],
    bool truncated = false,
  }) {
    if (!paths.contains(rootPath) || paths.length > maxLibraries ||
        paths.toSet().length != paths.length) {
      throw const FormatException('Invalid native graph node list');
    }
    final aliases = <String, Set<String>>{};
    for (final path in knownPaths ?? paths) {
      if (!path.contains('/') ||
          !path.startsWith('$abiDirectory/') ||
          path.substring(0, path.lastIndexOf('/')) != abiDirectory) {
        throw const FormatException('Native library outside selected ABI');
      }
      final basename = path.substring(path.lastIndexOf('/') + 1);
      aliases.putIfAbsent(basename, () => <String>{}).add(path);
      final soname = reports[path]?.soname;
      if (soname != null && soname.isNotEmpty) {
        aliases.putIfAbsent(soname, () => <String>{}).add(path);
      }
    }

    final scannedPaths = paths.toSet();
    final nodes = <NativeDependencyNode>[
      for (final path in paths)
        NativeDependencyNode(
          path: path,
          soname: reports[path]?.soname,
          inspected: reports.containsKey(path),
          warning: failures[path],
        ),
    ];
    final edges = <NativeDependencyEdge>[];
    final warnings = <String>[...additionalWarnings];
    for (final path in paths) {
      final report = reports[path];
      if (report == null) continue;
      if (report.truncated || report.warnings.isNotEmpty) {
        if (warnings.length < 24) {
          warnings.add('$path: partial or limited dependency data');
        }
      }
      for (final needed in report.needed) {
        final candidates = aliases[needed]?.toList() ?? <String>[];
        candidates.sort();
        if (candidates.isEmpty) {
          edges.add(NativeDependencyEdge(
            fromPath: path,
            neededName: needed,
            status: NativeDependencyStatus.notPackaged,
          ));
        } else if (candidates.length == 1) {
          edges.add(NativeDependencyEdge(
            fromPath: path,
            neededName: needed,
            status: scannedPaths.contains(candidates.single)
                ? NativeDependencyStatus.packaged
                : NativeDependencyStatus.packagedNotScanned,
            toPath: candidates.single,
          ));
        } else {
          edges.add(NativeDependencyEdge(
            fromPath: path,
            neededName: needed,
            status: NativeDependencyStatus.ambiguous,
            candidates: candidates,
          ));
        }
      }
    }

    // DFS marks back-edges as potential cycles. Nodes are bounded to 64.
    final outgoing = <String, List<String>>{};
    for (final edge in edges) {
      if (edge.toPath == null) continue;
      outgoing.putIfAbsent(edge.fromPath, () => <String>[]).add(edge.toPath!);
    }
    final colors = <String, int>{};
    final stack = <String>[];
    final cycles = <String>[];
    void visit(String path) {
      colors[path] = 1;
      stack.add(path);
      for (final target in outgoing[path] ?? const <String>[]) {
        if (cycles.length >= 16) break;
        if (colors[target] == 1) {
          final at = stack.indexOf(target);
          if (at >= 0) {
            cycles.add([...stack.skip(at), target]
                .map((p) => p.substring(p.lastIndexOf('/') + 1))
                .join(' → '));
          }
        } else if (colors[target] != 2) {
          visit(target);
        }
      }
      stack.removeLast();
      colors[path] = 2;
    }
    for (final path in paths) {
      if (colors[path] == null) visit(path);
    }
    final skippedCount = nodes.where((n) => !n.inspected).length;
    if (skippedCount > 0) {
      warnings.add('$skippedCount packaged libraries could not be inspected');
    }

    return NativeDependencyGraph(
      rootPath: rootPath,
      abiDirectory: abiDirectory,
      nodes: nodes,
      edges: edges,
      cycles: cycles,
      warnings: warnings,
      truncated: truncated || skippedCount > 0 ||
          reports.values.any((r) => r.truncated || r.warnings.isNotEmpty),
    );
  }
}
