import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/apk_report.dart';
import 'android_manifest_parser.dart';

class SourceProjectImport {
  const SourceProjectImport._();
  static const maxBytes = 128 * 1024 * 1024;
  static const maxMember = 24 * 1024 * 1024;
  static const maxFiles = 8000;
  static const maxEntries = 16000;

  static bool ignored(String path) => path.split('/').any((part) {
    final name = part.toLowerCase();
    return const {'.git', '.gradle', '.dart_tool', '.idea', 'build',
      'node_modules', '.cxx', 'local.properties'}.contains(name) ||
      name == '.env' || name.startsWith('.env.') ||
      name.endsWith('.jks') || name.endsWith('.keystore') ||
      name.endsWith('.p12') || name.endsWith('.pem') || name.endsWith('.key') ||
      name == 'key.properties';
  });

  static String safePath(String input) {
    final path = input.endsWith('/') ? input.substring(0, input.length - 1) : input;
    if (path.isEmpty || path.length > 512 || path.contains('\\') ||
        path.split('/').length > 32 || path.split('/').any((part) =>
          part.isEmpty || part == '.' || part == '..' || part.length > 150 ||
          part.endsWith('.') || part.endsWith(' ') ||
          RegExp(r'[<>:"|?*\x00-\x1f]').hasMatch(part) ||
          RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
            caseSensitive: false).hasMatch(part))) {
      throw const FormatException('Unsafe or non-portable source project path');
    }
    return path;
  }

  static String? framework(Iterable<String> paths) {
    final names = paths.map((s) => s.toLowerCase()).toList();
    final flutter = names.any((s) => s == 'pubspec.yaml' || s.endsWith('/pubspec.yaml')) &&
        names.any((s) => s.endsWith('/main.dart') || s == 'main.dart');
    if (flutter) return 'Flutter source project';
    if (names.any((s) => s.endsWith('build.gradle') || s.endsWith('build.gradle.kts')) &&
        names.any((s) => s.endsWith('androidmanifest.xml'))) {
      return names.any((s) => s.endsWith('.kt')) ? 'Android Gradle / Kotlin' :
          'Android Gradle / Java';
    }
    if (names.any((s) => s.endsWith('androidmanifest.xml'))) {
      return 'Android source project';
    }
    return null;
  }

  // Detect source ZIP separately from APK containers; do not extract arbitrary
  // package archives as editable projects.
  static bool isSourceZip(String path) {
    final file = File(path);
    if (file.lengthSync() > maxBytes) return false;
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input, throwOnError: true);
      if (archive.files.length > maxEntries) {
        throw const FormatException('Too many archive entries');
      }
      return framework(archive.files.where((f) => f.isFile && !ignored(f.name))
        .map((f) => f.name)) != null;
    } finally {
      input.close();
    }
  }

  static Future<void> extractZip(String path, String destination) async {
    if (File(path).lengthSync() > maxBytes) {
      throw const FormatException('Source ZIP exceeds 128 MiB');
    }
    final root = Directory(destination);
    if (await root.exists()) throw const FormatException('Destination already exists');
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input, throwOnError: true);
      if (archive.files.length > maxEntries) {
        throw const FormatException('Too many ZIP entries');
      }
      final seen = <String>{};
      final selected = <(ArchiveFile, String)>[];
      var total = 0;
      for (final entry in archive.files) {
        final name = safePath(entry.name);
        if (!seen.add(name.toLowerCase()) || entry.isSymbolicLink) {
          throw const FormatException('Duplicate or symbolic-link ZIP entry');
        }
        if (!entry.isFile || ignored(name)) continue;
        if (entry.size < 0 || entry.size > maxMember ||
            selected.length >= maxFiles || entry.size > maxBytes - total) {
          throw const FormatException('Source ZIP exceeds extraction budget');
        }
        total += entry.size;
        selected.add((entry, name));
      }
      if (framework(selected.map((r) => r.$2)) == null) {
        throw const FormatException('No Android or Flutter source project markers');
      }
      await root.create(recursive: true);
      for (final (entry, name) in selected) {
        final bytes = entry.readBytes();
        if (bytes == null || bytes.length != entry.size || bytes.length > maxMember) {
          throw const FormatException('ZIP member length mismatch');
        }
        final target = File(p.joinAll([root.path, ...name.split('/')]));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(bytes, flush: true);
        entry.clear();
      }
    } catch (_) {
      if (await root.exists()) await root.delete(recursive: true);
      rethrow;
    } finally {
      input.close();
    }
  }

  static Future<void> copyFolder(String source, String destination) async {
    final base = await Directory(source).resolveSymbolicLinks();
    final root = Directory(destination);
    final parent = await root.parent.resolveSymbolicLinks();
    if (p.isWithin(base, parent) || p.equals(base, parent) || await root.exists()) {
      throw const FormatException('Choose a source outside the app copy destination');
    }
    final seen = <String>{};
    var entries = 0, files = 0, total = 0;
    try {
      await root.create();
      final pending = <Directory>[Directory(base)];
      while (pending.isNotEmpty) {
        final directory = pending.removeLast();
        await for (final entity in directory.list(followLinks: false)) {
          if (++entries > maxEntries) throw const FormatException('Too many source entries');
          final name = safePath(p.relative(entity.path, from: base).replaceAll('\\', '/'));
          if (ignored(name)) continue;
          if (!seen.add(name.toLowerCase())) throw const FormatException('Conflicting paths');
          if (entity is Directory) {
            pending.add(entity);
          } else if (entity is File) {
            final canonical = await entity.resolveSymbolicLinks();
            if (!p.isWithin(base, canonical)) throw const FormatException('Source path escaped folder');
            final size = await entity.length();
            if (++files > maxFiles || size > maxMember || size > maxBytes - total) {
              throw const FormatException('Source folder exceeds copy limits');
            }
            final target = File(p.joinAll([root.path, ...name.split('/')]));
            await target.parent.create(recursive: true);
            final sink = target.openWrite();
            var copied = 0;
            try {
              await for (final bytes in entity.openRead(0, size + 1)) {
                copied += bytes.length;
                if (copied > size) throw const FormatException('Source changed while copying');
                sink.add(bytes);
                await sink.flush();
              }
            } finally { await sink.close(); }
            if (copied != size) throw const FormatException('Source changed while copying');
            total += copied;
          } else {
            throw const FormatException('Source links are not imported');
          }
        }
      }
    } catch (_) {
      if (await root.exists()) await root.delete(recursive: true);
      rethrow;
    }
  }

  static Future<ApkReport> describe(String root, String name, String id) async {
    final items = <ApkEntry>[];
    final hashes = <String>[];
    var total = 0;
    final base = await Directory(root).resolveSymbolicLinks();
    await for (final entity in Directory(base).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = safePath(p.relative(entity.path, from: base).replaceAll('\\','/'));
      final size = await entity.length();
      if (items.length >= maxFiles || size > maxMember || size > maxBytes - total) {
        throw const FormatException('Copied project exceeds inspection limits');
      }
      total += size;
      items.add(ApkEntry(name: relative, size: size, isFile: true));
      final hash = await sha256.bind(entity.openRead(0, size + 1)).first;
      hashes.add('$relative:$hash');
    }
    final kind = framework(items.map((e) => e.name));
    if (kind == null) throw const FormatException('No Android or Flutter project detected');
    items.sort((a,b) => a.name.compareTo(b.name));
    hashes.sort();
    var manifest = const ManifestInfo();
    final manifests = items.where((e) => e.name.endsWith('AndroidManifest.xml') &&
        e.size <= 4 * 1024 * 1024).toList()
      ..sort((a,b) => (a.name.endsWith('src/main/AndroidManifest.xml') ? 0 : 1)
        .compareTo(b.name.endsWith('src/main/AndroidManifest.xml') ? 0 : 1));
    if (manifests.isNotEmpty) {
      final bytes = await File(p.joinAll([base, ...manifests.first.name.split('/')])).readAsBytes();
      manifest = AndroidManifestParser.parse(bytes);
    }
    return ApkReport(id: id, fileName: name, localPath: base, size: total,
      sha256: sha256.convert(utf8.encode(hashes.join('\n'))).toString(),
      importedAt: DateTime.now(), entries: items, entryCount: items.length,
      dexFiles: const [], nativeLibraries: const [], manifest: manifest,
      framework: kind, warnings: const [
        'Imported source copy. Generated caches and common signing/secret files excluded; no build verification.'
      ], recoveredFolderPath: base, recoveredFileCount: items.length, sourceProject: true);
  }

  /// Export the copied source and binary assets. Drafts overlay existing files only.
  static Future<Uint8List> exportZip(String root, Map<String, String> drafts) async {
    final base = await Directory(root).resolveSymbolicLinks();
    final archive = Archive();
    final used = <String>{};
    var total = 0;
    await for (final entity in Directory(base).list(recursive: true, followLinks: false)) {
      if (entity is Directory) continue;
      if (entity is! File) throw const FormatException('Cannot export symbolic links');
      final relative = safePath(p.relative(entity.path, from: base).replaceAll('\\','/'));
      if (ignored(relative)) continue;
      final size = await entity.length();
      if (size > maxMember || used.length >= maxFiles || size > maxBytes - total ||
          !used.add(relative)) throw const FormatException('Export limit exceeded');
      final bytes = drafts.containsKey(relative) ? utf8.encode(drafts[relative]!) :
          await entity.readAsBytes();
      if (bytes.length > maxMember || bytes.length > maxBytes - total) {
        throw const FormatException('Export limit exceeded');
      }
      total += bytes.length;
      archive.addFile(ArchiveFile(relative, bytes.length, bytes));
    }
    if (!used.containsAll(drafts.keys)) throw const FormatException('Draft file no longer exists');
    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }
}
