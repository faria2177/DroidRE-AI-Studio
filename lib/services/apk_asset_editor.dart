import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import '../models/apk_report.dart';
import 'package_binary_reader.dart';

class ApkAssetEditResult {
  const ApkAssetEditResult(this.bytes, this.beforeHash, this.afterHash,
      this.unchanged, this.removedSignatures);
  final Uint8List bytes;
  final String beforeHash, afterHash;
  final int unchanged, removedSignatures;
  String get outputHash => sha256.convert(bytes).toString();
}

/// Bounded local asset replacement. This is ZIP repacking, not compilation,
/// alignment or signature verification.
class ApkAssetEditor {
  const ApkAssetEditor._();
  static const maxInput = 48 * 1024 * 1024;
  static const maxExpanded = 64 * 1024 * 1024;
  static const maxAsset = 512 * 1024;
  static const maxEntries = 10000;

  static bool _safe(String name) {
    if (name.isEmpty || name.length > 1024 || name.startsWith('/') ||
        name.contains('\\') || name.contains('\u0000') || name.contains(':')) {
      return false;
    }
    final path = name.endsWith('/') ? name.substring(0, name.length - 1) : name;
    return path.split('/').every((part) =>
        part.isNotEmpty && part != '.' && part != '..');
  }

  static bool editable(String name) => _safe(name) &&
      name.startsWith('assets/') &&
      RegExp(r'\.(txt|json|properties|xml|css|md)$', caseSensitive: false)
          .hasMatch(name);

  static bool _signature(String name) {
    final upper = name.toUpperCase();
    if (!upper.startsWith('META-INF/')) {
      return false;
    }
    final leaf = upper.substring(9);
    return !leaf.contains('/') &&
        (leaf == 'MANIFEST.MF' || leaf.startsWith('SIG-') ||
          leaf.endsWith('.SF') || leaf.endsWith('.RSA') ||
          leaf.endsWith('.DSA') || leaf.endsWith('.EC'));
  }

  static String _text(String name, List<int> bytes) {
    if (!editable(name) || bytes.length > maxAsset || bytes.contains(0)) {
      throw const FormatException('Asset must be bounded UTF-8 text');
    }
    return utf8.decode(bytes);
  }

  static void _check(ApkReport report) {
    if (!report.fileName.toLowerCase().endsWith('.apk') ||
        File(report.localPath).lengthSync() > maxInput) {
      throw const FormatException('Only APK input up to 48 MiB is supported');
    }
  }

  static Future<String> load(ApkReport report, String name) => Isolate.run(() {
    _check(report);
    return _text(name, PackageBinaryReader.read(apkPath: report.localPath,
        entryName: name, maxBytes: maxAsset));
  });

  static Future<ApkAssetEditResult> rebuild(ApkReport report, String name,
      String replacement) => Isolate.run(() {
    _check(report);
    final input = File(report.localPath).readAsBytesSync();
    if (input.length > maxInput || sha256.convert(input).toString() != report.sha256) {
      throw const FormatException('Imported APK changed; reimport first');
    }
    return rebuildBytes(input, name, replacement);
  });

  static ApkAssetEditResult rebuildBytes(Uint8List input, String name,
      String replacement) {
    if (input.length > maxInput || !editable(name) ||
        replacement.length > maxAsset) {
      throw const FormatException('Invalid APK or asset size/path');
    }
    final updated = Uint8List.fromList(utf8.encode(replacement));
    _text(name, updated);
    if (name.toLowerCase().endsWith('.json')) {
      jsonDecode(replacement);
    }
    final archive = ZipDecoder().decodeBytes(input, throwOnError: true);
    if (archive.files.length > maxEntries) {
      throw const FormatException('Too many APK entries');
    }
    final names = <String>{};
    var expanded = 0;
    for (final entry in archive.files) {
      if (!_safe(entry.name) || !names.add(entry.name) || entry.isSymbolicLink ||
          entry.size < 0 || (!entry.isFile && entry.size != 0)) {
        throw const FormatException('Unsafe or duplicate member');
      }
      expanded += entry.size;
      if (expanded > maxExpanded) {
        throw const FormatException('Expanded data exceeds 64 MiB');
      }
    }
    if (!archive.files.any((e) => e.isFile && e.name == 'AndroidManifest.xml') ||
        !archive.files.any((e) => e.isFile && e.name == name)) {
      throw const FormatException('Manifest or asset missing');
    }
    final output = Archive();
    final hashes = <String, String>{};
    String? before;
    var unchanged = 0;
    var removed = 0;
    var outputSize = 0;
    for (final entry in archive.files) {
      if (!entry.isFile) {
        continue;
      }
      if (_signature(entry.name)) {
        removed++;
        continue;
      }
      final bytes = entry.readBytes();
      if (bytes == null || bytes.length != entry.size) {
        throw const FormatException('Cannot read complete member');
      }
      final edited = entry.name == name;
      final oldHash = sha256.convert(bytes).toString();
      if (edited) {
        _text(name, bytes);
        before = oldHash;
      } else {
        unchanged++;
      }
      final payload = edited ? updated : bytes;
      outputSize += payload.length;
      if (outputSize > maxExpanded) {
        throw const FormatException('Repacked data exceeds 64 MiB');
      }
      hashes[entry.name] = edited ? sha256.convert(payload).toString() : oldHash;
      output.addFile(ArchiveFile.bytes(entry.name, payload));
    }
    if (before == null || before == hashes[name]) {
      throw const FormatException('No asset content changed');
    }
    final encoded = Uint8List.fromList(ZipEncoder().encode(output));
    if (encoded.length > maxExpanded) {
      throw const FormatException('Output exceeds 64 MiB');
    }
    final verified = ZipDecoder().decodeBytes(encoded, throwOnError: true);
    final seen = <String>{};
    for (final item in verified.files) {
      final bytes = item.readBytes();
      if (!item.isFile || !seen.add(item.name) || bytes == null ||
          hashes[item.name] != sha256.convert(bytes).toString()) {
        throw const FormatException('Repacked payload verification failed');
      }
    }
    if (seen.length != hashes.length) {
      throw const FormatException('Repacked member count differs');
    }
    return ApkAssetEditResult(encoded, before, hashes[name]!, unchanged, removed);
  }
}
