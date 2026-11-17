import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

import 'elf_section_inspector.dart';
import 'flutter_aot_inspector.dart';
import 'package_binary_reader.dart';
import 'elf_inspector.dart';

/// Printable byte runs are evidence, not deserialized Dart String objects.
class FlutterStructureInspector {
  const FlutterStructureInspector._();
  static const maxScanBytes = 2 * 1024 * 1024;
  static const maxStrings = 1000;
  static const maxAssets = 5000;
  static const maxStringLength = 256;
  static const assetRoot = 'assets/flutter_assets/';

  static Future<Map<String, Object?>> inspect(String apk, String entry) =>
      Isolate.run(() {
        final bytes = PackageBinaryReader.read(apkPath: apk,
            entryName: entry, maxBytes: ElfInspector.maxBytes);
        final binary = scanBinary(bytes);
        final input = InputFileStream(apk);
        try {
          final archive = ZipDecoder().decodeStream(input, throwOnError: true);
          if (archive.files.length > 200000) {
            throw const FormatException('Too many archive entries');
          }
          return {
            'schemaVersion': 1,
            'elfEntry': entry,
            'binary': binary,
            'assets': inventory(archive),
            'scope': 'Static byte and path evidence only. No Dart object decoding, '
                'dependency version recovery, or original source reconstruction.',
          };
        } finally {
          input.close();
        }
      });

  static Map<String, Object?> scanBinary(Uint8List bytes, {
    int byteLimit = maxScanBytes, int resultLimit = maxStrings,
  }) {
    if (byteLimit < 1 || byteLimit > maxScanBytes ||
        resultLimit < 1 || resultLimit > maxStrings) {
      throw const FormatException('Invalid string scan bounds');
    }
    final snapshot = FlutterAotInspector.inspectBytes(bytes);
    final sections = ElfSectionInspector.inspectBytes(bytes);
    final ranges = <(int, int, String)>[];
    final warnings = <String>[];
    final known = snapshot.regions.where((item) =>
        item.role.endsWith('data') && item.availableBytes > 0);
    for (final item in known) {
      final range = (item.fileOffset, item.availableBytes, item.role);
      if (!ranges.any((r) => r.$1 == range.$1 && r.$2 == range.$2)) {
        ranges.add(range);
      }
    }
    final fallback = ranges.isEmpty;
    if (fallback) {
      warnings.add('No sized snapshot data region; scanning non-executable read-only allocated PROGBITS sections instead.');
      for (final section in sections.sections) {
        if (section.fileBacked && section.type == 'PROGBITS' &&
            section.flags.contains('ALLOC') && !section.flags.contains('EXEC') &&
            !section.flags.contains('WRITE') && !section.flags.contains('COMPRESSED') &&
            section.size > 0) {
          ranges.add((section.fileOffset, section.size, 'section:${section.name}'));
        }
      }
    }
    final hits = <Map<String, Object?>>[];
    final offsets = <int>{};
    var scanned = 0;
    var partial = snapshot.partial || sections.truncated || fallback;
    for (final range in ranges) {
      if (scanned >= byteLimit || hits.length >= resultLimit) {
        partial = true;
        break;
      }
      final count = range.$2.clamp(0, byteLimit - scanned).toInt();
      final stop = range.$1 + count;
      if (count != range.$2) {
        partial = true;
      }
      var pos = range.$1;
      while (pos < stop && hits.length < resultLimit) {
        final start = pos;
        while (pos < stop && bytes[pos] >= 32 && bytes[pos] <= 126) {
          pos++;
        }
        final length = pos - start;
        // Reject a run cut off by the byte budget; never call it complete.
        if (length >= 5 && (pos < stop || count == range.$2) &&
            offsets.add(start)) {
          final visible = length.clamp(0, maxStringLength).toInt();
          final text = ascii.decode(bytes.sublist(start, start + visible));
          hits.add({
            'fileOffset': '0x${start.toRadixString(16)}',
            'region': range.$3,
            'text': text,
            'length': length,
            'truncated': visible != length,
            'kind': classify(text),
          });
        }
        if (pos < stop) {
          pos++;
        }
      }
      scanned += pos - range.$1;
      if (pos < stop || hits.length >= resultLimit) {
        partial = true;
      }
    }
    return {
      'snapshotLayout': snapshot.layout,
      'snapshotRegions': snapshot.regions.map((r) => r.toJson()).toList(),
      'fallbackSectionScan': fallback,
      'scannedBytes': scanned,
      'partial': partial,
      'warnings': [...snapshot.warnings, ...warnings],
      'strings': hits,
    };
  }

  static String classify(String value) {
    if (value.startsWith('package:') || value.startsWith('dart:')) {
      return 'dart-uri-like';
    }
    if (value.startsWith('https://') || value.startsWith('http://')) {
      return 'url-like';
    }
    if (value.endsWith('.dart')) {
      return 'source-path-like';
    }
    if (value.startsWith('assets/') || value.startsWith('packages/')) {
      return 'asset-path-like';
    }
    return 'printable-ascii';
  }

  static Map<String, Object?> inventory(Archive archive) {
    final entries = <Map<String, Object?>>[];
    final packages = <String>{};
    final seen = <String>{};
    var count = 0;
    var unsafe = 0;
    var duplicate = 0;
    for (final entry in archive.files) {
      if (!entry.name.startsWith(assetRoot) || !entry.isFile) {
        continue;
      }
      final relative = entry.name.substring(assetRoot.length);
      if (entry.isSymbolicLink || entry.size < 0 || relative.length > 2048 ||
          relative.contains('\\') || relative.contains(':') ||
          relative.contains('\u0000') ||
          relative.split('/').any((p) => p.isEmpty || p == '.' || p == '..')) {
        unsafe++;
        continue;
      }
      if (!seen.add(relative)) {
        duplicate++;
        continue;
      }
      count++;
      if (entries.length >= maxAssets) {
        continue;
      }
      final parts = relative.split('/');
      final pkg = parts.length >= 3 && parts.first == 'packages' ? parts[1] : null;
      if (pkg != null) {
        packages.add(pkg);
      }
      entries.add({
        'path': relative,
        'bytes': entry.size,
        'packageFolder': pkg,
        'kind': switch (relative) {
          'AssetManifest.bin' || 'AssetManifest.json' || 'FontManifest.json' ||
          'NativeAssetsManifest.json' => 'manifest-file',
          'NOTICES' || 'NOTICES.Z' => 'license-notices',
          _ => 'asset',
        },
      });
    }
    return {
      'assetCount': count,
      'packageFolders': packages.toList()..sort(),
      'entries': entries,
      'unsafeSkipped': unsafe,
      'duplicatesSkipped': duplicate,
      'partial': count > entries.length || unsafe > 0 || duplicate > 0,
      'note': 'Paths only; package folders are not a complete dependency list.',
    };
  }
}
