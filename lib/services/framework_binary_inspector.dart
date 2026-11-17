import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package_binary_reader.dart';

/// Narrow format inspection; no JavaScript, native or managed code runs.
class FrameworkBinaryInspector {
  const FrameworkBinaryInspector._();
  static const maxBytes = 32 * 1024 * 1024;
  static const maxScan = 1024 * 1024;
  static const maxStrings = 500;
  static const hermesMagic = 0x1f1903c103bc1fc6;
  static const metadataMagic = 0xfab11baf;

  static bool supports(String path) =>
      path == 'assets/index.android.bundle' ||
      path.endsWith('/global-metadata.dat') ||
      (path.startsWith('assets/app/') &&
          RegExp(r'\.(js|json)$', caseSensitive: false).hasMatch(path));

  static Future<Map<String, Object?>> inspect(String apk, String entry) =>
      Isolate.run(() => inspectBytes(entry, PackageBinaryReader.read(
        apkPath: apk, entryName: entry, maxBytes: maxBytes,
      )));

  static Map<String, Object?> inspectBytes(String entry, Uint8List bytes) {
    if (!supports(entry) || bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Unsupported framework member or size');
    }
    final data = ByteData.sublistView(bytes);
    final result = <String, Object?>{
      'schemaVersion': 1, 'entry': entry, 'bytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      'scope': 'Static evidence only; no original source or bytecode decompilation.',
    };
    int u32(int offset) => data.getUint32(offset, Endian.little);
    if (entry.endsWith('/global-metadata.dat')) {
      if (bytes.length < 8 || u32(0) != metadataMagic) {
        return {...result, 'kind': 'unknown-metadata', 'partial': true,
          'note': 'IL2CPP magic not observed; no encryption or format inference.'};
      }
      final version = u32(4);
      result.addAll({'kind': 'unity-il2cpp-metadata', 'version': version, 'partial': true});
      // Classic header prefix only for known layouts. No version subvariant inference.
      if (!const {24, 27, 29}.contains(version) || bytes.length < 32) {
        return {...result, 'note': 'Unsupported metadata layout; magic/version only.'};
      }
      final ranges = <Map<String, Object>>[];
      final spans = <(int, int)>[];
      for (final (name, at) in [('literal-table', 8), ('literal-data', 16), ('metadata-strings', 24)]) {
        final offset = u32(at);
        final length = u32(at + 4);
        if (offset > bytes.length || length > bytes.length - offset ||
            (length > 0 && offset < 32)) {
          throw const FormatException('IL2CPP metadata prefix range outside file');
        }
        if (length > 0) {
          if (spans.any((r) => offset < r.$2 && r.$1 < offset + length)) {
            throw const FormatException('Overlapping IL2CPP metadata prefix ranges');
          }
          spans.add((offset, offset + length));
        }
        ranges.add({'name': name, 'offset': offset, 'bytes': length});
      }
      result['ranges'] = ranges;
      result['strings'] = _strings(bytes, u32(24), u32(28), terminated: true);
      result['note'] = 'Classic metadata string names only; no type/method mapping, C# or native registration recovery.';
      return result;
    }
    if (bytes.length >= 8 && data.getUint64(0, Endian.little) == hermesMagic) {
      if (bytes.length < 64) {
        throw const FormatException('Truncated Hermes header prefix');
      }
      final declared = u32(32);
      if (declared < 64 || declared > bytes.length) {
        throw const FormatException('Hermes declared file length outside member');
      }
      final count = u32(40);
      final globalIndex = u32(36);
      if (count == 0 || globalIndex >= count) {
        throw const FormatException('Invalid Hermes function header counts');
      }
      return {...result, 'kind': 'hermes-bytecode', 'version': u32(8),
        'declaredBytes': declared, 'sourceHashHeader': _hex(bytes.sublist(12, 32)),
        'globalCodeIndex': globalIndex, 'functionCountHeader': count,
        'stringCountHeader': u32(52), 'stringStorageBytesHeader': u32(60),
        'strings': _strings(bytes, 64, declared - 64),
        'partial': true,
        'note': 'Common header prefix fields are observations; raw printable runs are not decoded Hermes string-table entries.'};
    }
    final length = bytes.length.clamp(0, maxScan).toInt();
    String text;
    try {
      // Validate the full bounded member; preview is clipped separately.
      text = utf8.decode(bytes);
      if (text.runes.any((c) => c < 32 && c != 9 && c != 10 && c != 13)) {
        throw const FormatException('Non-text control bytes');
      }
    } on FormatException {
      return {...result, 'kind': 'unknown-binary', 'partial': true,
        'strings': _strings(bytes, 0, length),
        'note': 'No supported signature or strict UTF-8 text; no assumed bytecode format.'};
    }
    final preview = text.length > 12000 ? text.substring(0, 12000) : text;
    final isNativeScriptPath = entry.startsWith('assets/app/');
    result.addAll({
      'kind': isNativeScriptPath ? 'nativescript-text-candidate' : 'react-native-text-bundle-candidate',
      'preview': preview, 'partial': preview.length != text.length,
      'note': 'Text by path and UTF-8 evidence; not proof of executable JavaScript or original source.',
    });
    if (isNativeScriptPath && entry.endsWith('/package.json') && bytes.length <= 256 * 1024) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          final names = <String>{};
          for (final section in ['dependencies', 'devDependencies']) {
            final values = decoded[section];
            if (values is Map) {
              names.addAll(values.keys.whereType<String>().where((n) => n.length <= 200).take(200));
            }
          }
          result['packageName'] = decoded['name'] is String ? decoded['name'] : null;
          result['declaredVersion'] = decoded['version'] is String ? decoded['version'] : null;
          result['declaredDependencyNames'] = names.toList()..sort();
          result['dependencyNote'] = 'Declared names only, not installed versions; bounded per section.';
        }
      } on FormatException {
        result['packageWarning'] = 'Invalid package JSON';
      }
    }
    return result;
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<Map<String, Object>> _strings(Uint8List bytes, int offset,
      int size, {bool terminated = false}) {
    final end = offset + size.clamp(0, maxScan).toInt();
    final hits = <Map<String, Object>>[];
    var pos = offset;
    while (pos < end && hits.length < maxStrings) {
      final start = pos;
      while (pos < end && bytes[pos] >= 32 && bytes[pos] <= 126) {
        pos++;
      }
      if (pos - start >= 4 && (!terminated ||
          ((start == offset || bytes[start - 1] == 0) && pos < end && bytes[pos] == 0)) &&
          (pos < end || end == offset + size)) {
        final stop = (start + 256).clamp(start, pos).toInt();
        hits.add({'offset': start, 'text': ascii.decode(bytes.sublist(start, stop)),
          'clipped': stop != pos});
      }
      if (pos < end) {
        pos++;
      }
    }
    return hits;
  }
}
