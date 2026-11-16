import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/apk_report.dart';
import 'source_recovery_bundle.dart';

@immutable
class RecoveredFolderResult {
  const RecoveredFolderResult({
    required this.folderPath,
    required this.filesWritten,
    required this.dexFilesVisited,
    required this.classesExported,
    required this.methodsExported,
    required this.partial,
  });

  final String folderPath;
  final int filesWritten;
  final int dexFilesVisited;
  final int classesExported;
  final int methodsExported;
  final bool partial;
}

/// Materializes a bounded recovery bundle into a real directory tree.
///
/// No all-files permissions or hardcoded /sdcard paths are used. On Android
/// this uses the app-specific external-files directory, which is scoped by
/// Android and may not be browseable by other file manager apps.
class SourceRecoveryFolderService {
  const SourceRecoveryFolderService._();

  static const folderRoot = 'DroidRE_SourceProjects';
  static const maxUnpackedBytes = 48 * 1024 * 1024;
  static const maxOutputFiles = 600;
  static const maxPreviewBytes = 64 * 1024;

  static Future<Directory> storageRoot() async {
    Directory? external;
    try {
      external = await getExternalStorageDirectory();
    } catch (_) {
      // Some non-Android platforms do not expose an external-files path.
    }
    final base = external ?? await getApplicationSupportDirectory();
    return Directory('${base.path}/$folderRoot');
  }

  /// Automatically invoked *after* an APK has been safely imported and
  /// indexed. Failing to recover source never invalidates the APK import.
  static Future<RecoveredFolderResult> generate(ApkReport report) async {
    final bundle = await SourceRecoveryBundle.fromProject(report);
    final root = await storageRoot();
    return writeBundle(
      root: root,
      projectId: report.id,
      packageName: report.manifest.packageName,
      bundle: bundle,
    );
  }

  static String _safeName(String name) {
    final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (safe.length > 55) {
      return safe.substring(0, 55);
    }
    return safe.isEmpty ? 'unknown' : safe;
  }

  static Future<RecoveredFolderResult> writeBundle({
    required Directory root,
    required String projectId,
    required String packageName,
    required SourceRecoveryResult bundle,
  }) => Isolate.run(() => _writeBundle(
    rootPath: root.path,
    projectId: projectId,
    packageName: packageName,
    bundle: bundle,
  ));

  static Future<RecoveredFolderResult> _writeBundle({
    required String rootPath,
    required String projectId,
    required String packageName,
    required SourceRecoveryResult bundle,
  }) async {
    final root = Directory(rootPath);
    await root.create(recursive: true);
    final targetName = '${_safeName(packageName)}_${_safeName(projectId)}';
    final finalFolder = Directory('${root.path}/$targetName');
    if (await finalFolder.exists()) {
      // Do not overwrite any previously generated or user-edited files.
      throw const FileSystemException('Recovery folder already exists');
    }
    final staging = await Directory(
      '${root.path}/.$targetName.recovering_'
      '${DateTime.now().microsecondsSinceEpoch}',
    ).create();
    var written = 0;
    try {
      final zip = ZipDecoder().decodeBytes(bundle.zipBytes, throwOnError: true);
      if (zip.files.length > maxOutputFiles) {
        throw const FormatException('Recovery ZIP has too many members');
      }
      var total = 0;
      final seen = <String>{};
      final members = <(String, ArchiveFile)>[];
      for (final item in zip.files) {
        if (!item.isFile) {
          continue;
        }
        final path = item.name.replaceAll('\\', '/');
        final segments = path.split('/');
        if (path.startsWith('/') ||
            segments.any((part) => part.isEmpty || part == '.' ||
                part == '..' || part.contains(':')) ||
            item.isSymbolicLink || !seen.add(path)) {
          throw const FormatException(
              'Recovery ZIP contains an unsafe or duplicate path');
        }
        if (item.size < 0 || item.size > maxUnpackedBytes ||
            total + item.size > maxUnpackedBytes) {
          throw const FormatException(
              'Recovery ZIP exceeds extracted size limit');
        }
        total += item.size;
        members.add((path, item));
      }

      for (final member in members) {
        final path = member.$1;
        final bytes = member.$2.readBytes();
        if (bytes == null || bytes.length != member.$2.size) {
          throw const FormatException('Recovery ZIP entry size mismatch');
        }
        final file = File('${staging.path}/$path');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: false);
        written++;
      }
      // The rename makes the finished folder visible only after all
      // files were successfully written.
      await staging.rename(finalFolder.path);
      return RecoveredFolderResult(
        folderPath: finalFolder.path,
        filesWritten: written,
        dexFilesVisited: bundle.dexFilesVisited,
        classesExported: bundle.classesExported,
        methodsExported: bundle.methodsExported,
        partial: bundle.partial,
      );
    } catch (_) {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
      rethrow;
    }
  }

  /// Lists only files beneath a generated folder (no symbolic links).
  static Future<List<String>> listRelativeFiles(String folderPath) async {
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      return const [];
    }
    final files = <String>[];
    await for (final entity in folder.list(
        recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final relative = entity.path.substring(folder.path.length + 1)
          .replaceAll('\\', '/');
      if (_isSafeRelativePath(relative)) {
        files.add(relative);
      }
      if (files.length >= maxOutputFiles) {
        break;
      }
    }
    files.sort();
    return files;
  }

  static bool _isSafeRelativePath(String value) {
    if (value.isEmpty || value.startsWith('/') || value.contains('\\')) {
      return false;
    }
    return value.split('/').every((segment) => segment.isNotEmpty &&
        segment != '.' && segment != '..' && !segment.contains(':'));
  }

  /// In-app preview only: rejects traversal and symlinks and is bounded.
  static Future<String> previewFile(
    String folderPath,
    String relativePath,
  ) async {
    if (!_isSafeRelativePath(relativePath)) {
      throw const FormatException('Unsafe recovered file path');
    }
    final folder = Directory(folderPath);
    final base = await folder.resolveSymbolicLinks();
    final file = File('$base/$relativePath');
    final resolved = await file.resolveSymbolicLinks();
    if (!resolved.startsWith('$base/')) {
      throw const FormatException('File points outside recovered folder');
    }
    final size = await file.length();
    if (size > maxPreviewBytes) {
      return 'This file is larger than the 64 KiB in-app text preview limit. '
          'Open it through the exported ZIP instead.';
    }
    final bytes = await file.readAsBytes();
    if (relativePath.endsWith('.bin')) {
      return 'Raw binary resource (${bytes.length} bytes)\n'
          '${bytes.take(256).map((v) =>
              v.toRadixString(16).padLeft(2, '0')).join(' ')}';
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
