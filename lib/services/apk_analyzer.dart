import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import '../models/apk_report.dart';
import 'android_manifest_parser.dart';

/// A real, read-only archive/manifest inventory, not a source decompiler.
class ApkAnalyzer {
  const ApkAnalyzer._();

  static Future<ApkReport> inspect({
    required String path,
    required String displayName,
    required String id,
  }) async {
    final file = File(path);
    final length = await file.length();
    if (length < 4) throw const FormatException('File is too small');
    if (length > 1024 * 1024 * 1024) {
      throw const FormatException('Files over 1 GiB need the worker engine');
    }
    final hash = await sha256.bind(file.openRead()).first;
    final input = InputFileStream(path);
    final warnings = <String>[];
    try {
      final archive = ZipDecoder().decodeStream(input, throwOnError: true);
      if (archive.files.length > 200000) {
        throw const FormatException('Too many archive entries');
      }
      final entries = <ApkEntry>[];
      final dex = <String>[];
      final native = <String>[];
      final names = <String>{};
      ManifestInfo manifest = const ManifestInfo();
      var suspicious = 0;
      for (final entry in archive.files) {
        final name = entry.name.replaceAll('\\', '/');
        if (name.startsWith('/') ||
            name.split('/').contains('..') ||
            entry.isSymbolicLink) {
          suspicious++;
          continue;
        }
        if (!names.add(name)) warnings.add('Duplicate entry: $name');
        if (entries.length < 10000) {
          entries.add(ApkEntry(
            name: name,
            size: entry.size,
            isFile: entry.isFile,
          ));
        }
        if (RegExp(r'(^|/)classes\d*\.dex$').hasMatch(name)) dex.add(name);
        if (name.startsWith('lib/') && name.endsWith('.so')) native.add(name);
        if (name == 'AndroidManifest.xml' && entry.size <= 4 * 1024 * 1024) {
          try {
            final bytes = entry.readBytes();
            if (bytes != null) {
              manifest = AndroidManifestParser.parse(Uint8List.fromList(bytes));
            }
          } on FormatException {
            warnings.add('Manifest could not be decoded');
          }
        }
      }
      if (suspicious != 0) {
        warnings.add('$suspicious unsafe archive paths were hidden');
      }
      if (archive.files.length > entries.length) {
        warnings.add('File list limited to 10,000 entries');
      }
      if (!manifest.decoded) {
        warnings.add('Manifest unavailable or in an unsupported format');
      }
      if (displayName.toLowerCase().endsWith('.aab')) {
        warnings.add('AAB module conversion requires bundletool (later phase)');
      }
      if (displayName.toLowerCase().endsWith('.apks') ||
          displayName.toLowerCase().endsWith('.xapk') ||
          displayName.toLowerCase().endsWith('.apkm')) {
        warnings.add('Container inspected; nested split APKs not yet decoded');
      }
      final framework = _detectFramework(names);
      return ApkReport(
        id: id,
        fileName: displayName,
        localPath: path,
        size: length,
        sha256: hash.toString(),
        importedAt: DateTime.now(),
        entries: entries,
        entryCount: archive.files.length,
        dexFiles: dex,
        nativeLibraries: native,
        manifest: manifest,
        framework: framework,
        warnings: warnings,
      );
    } finally {
      input.close();
    }
  }

  static String _detectFramework(Set<String> paths) {
    if (paths.any((name) => name.endsWith('/libflutter.so')) ||
        paths.any((name) => name.startsWith('assets/flutter_assets/'))) {
      return 'Flutter (indicators found)';
    }
    if (paths.contains('assets/index.android.bundle')) {
      return 'React Native (indicator found)';
    }
    if (paths.any((name) => name.contains('libunity.so'))) {
      return 'Unity (indicator found)';
    }
    if (paths.any((name) => name.endsWith('/libnativescript.so'))) {
      return 'NativeScript (indicator found)';
    }
    return 'Unknown / Native Android (not confirmed)';
  }
}
