import 'dart:convert';
import 'dart:typed_data';

import '../models/apk_report.dart';

/// Safely reads common metadata from a text or Android binary XML manifest.
/// It is not a full resources.arsc decoder.
class AndroidManifestParser {
  const AndroidManifestParser._();

  static ManifestInfo parse(Uint8List bytes) {
    if (bytes.isEmpty) return const ManifestInfo();
    final initial = utf8.decode(
      bytes.sublist(0, bytes.length < 96 ? bytes.length : 96),
      allowMalformed: true,
    );
    if (initial.trimLeft().startsWith('<')) {
      return _parseText(utf8.decode(bytes, allowMalformed: true));
    }
    try {
      return _parseBinary(bytes);
    } on FormatException {
      return const ManifestInfo();
    } on RangeError {
      return const ManifestInfo();
    }
  }

  static ManifestInfo _parseText(String xml) {
    String attribute(String body, String name) {
      final expression = RegExp('(?:android:)?$name\\s*=\\s*"([^"]*)"');
      return expression.firstMatch(body)?.group(1) ?? '';
    }

    final manifestTag = RegExp(r'<manifest\b[^>]*>').firstMatch(xml)?.group(0) ?? '';
    final sdkTag = RegExp(r'<uses-sdk\b[^>]*>').firstMatch(xml)?.group(0) ?? '';
    List<String> names(String tag) => RegExp('<$tag\\b[^>]*>')
        .allMatches(xml)
        .map((match) => attribute(match.group(0) ?? '', 'name'))
        .where((name) => name.isNotEmpty)
        .toList();

    return ManifestInfo(
      packageName: attribute(manifestTag, 'package'),
      versionCode: attribute(manifestTag, 'versionCode'),
      versionName: attribute(manifestTag, 'versionName'),
      minSdk: attribute(sdkTag, 'minSdkVersion'),
      targetSdk: attribute(sdkTag, 'targetSdkVersion'),
      permissions: names('uses-permission'),
      activities: names('activity'),
      services: names('service'),
      receivers: names('receiver'),
      providers: names('provider'),
      decoded: true,
    );
  }

  static ManifestInfo _parseBinary(Uint8List data) {
    if (data.length < 8 || _u16(data, 0) != 0x0003) {
      throw const FormatException('Not Android binary XML');
    }
    final xmlSize = _u32(data, 4);
    if (xmlSize < 8 || xmlSize > data.length) {
      throw const FormatException('Invalid XML document length');
    }
    final strings = <String>[];
    final metadata = <String, String>{};
    final permissions = <String>[];
    final activities = <String>[];
    final services = <String>[];
    final receivers = <String>[];
    final providers = <String>[];
    var sawManifest = false;
    var cursor = _u16(data, 2);
    var chunks = 0;
    while (cursor + 8 <= data.length && chunks++ < 100000) {
      final chunkType = _u16(data, cursor);
      final headerSize = _u16(data, cursor + 2);
      final chunkSize = _u32(data, cursor + 4);
      if (headerSize < 8 ||
          chunkSize < headerSize ||
          cursor + chunkSize > data.length) {
        throw const FormatException('Invalid binary XML chunk');
      }
      if (chunkType == 0x0001) {
        strings
          ..clear()
          ..addAll(_readStringPool(data, cursor, chunkSize));
      } else if (chunkType == 0x0102 && cursor + 36 <= data.length) {
        final tag = _fromPool(strings, _u32(data, cursor + 20));
        final attributeStart = _u16(data, cursor + 24);
        final attributeSize = _u16(data, cursor + 26);
        final count = _u16(data, cursor + 28);
        if (attributeSize < 20 || count > 10000) {
          throw const FormatException('Invalid attribute list');
        }
        final attrs = <String, String>{};
        final firstAttribute = cursor + 16 + attributeStart;
        for (var i = 0; i < count; i++) {
          final offset = firstAttribute + i * attributeSize;
          if (offset + 20 > cursor + chunkSize) {
            throw const FormatException('Truncated XML attribute');
          }
          final name = _fromPool(strings, _u32(data, offset + 4));
          final rawIndex = _u32(data, offset + 8);
          final type = data[offset + 15];
          final typedData = _u32(data, offset + 16);
          final value = rawIndex != 0xffffffff
              ? _fromPool(strings, rawIndex)
              : _typedValue(strings, type, typedData);
          attrs[name] = value;
        }
        if (tag == 'manifest' || tag == 'uses-sdk') {
          metadata.addAll(attrs);
          if (tag == 'manifest') sawManifest = true;
        } else {
          final name = attrs['name'];
          if (name != null && name.isNotEmpty) {
            switch (tag) {
              case 'uses-permission':
              case 'uses-permission-sdk-23':
                permissions.add(name);
                break;
              case 'activity':
              case 'activity-alias':
                activities.add(name);
                break;
              case 'service':
                services.add(name);
                break;
              case 'receiver':
                receivers.add(name);
                break;
              case 'provider':
                providers.add(name);
                break;
            }
          }
        }
      }
      cursor += chunkSize;
    }
    if (!sawManifest) throw const FormatException('Manifest root not found');
    return ManifestInfo(
      packageName: metadata['package'] ?? '',
      versionCode: metadata['versionCode'] ?? '',
      versionName: metadata['versionName'] ?? '',
      minSdk: metadata['minSdkVersion'] ?? '',
      targetSdk: metadata['targetSdkVersion'] ?? '',
      permissions: permissions,
      activities: activities,
      services: services,
      receivers: receivers,
      providers: providers,
      decoded: true,
    );
  }

  static List<String> _readStringPool(
    Uint8List bytes,
    int start,
    int chunkSize,
  ) {
    if (chunkSize < 28) throw const FormatException('Small string pool');
    final count = _u32(bytes, start + 8);
    final flags = _u32(bytes, start + 16);
    final stringsStart = _u32(bytes, start + 20);
    if (count > 100000 || 28 + count * 4 > chunkSize) {
      throw const FormatException('Invalid string count');
    }
    final isUtf8 = flags & 0x100 != 0;
    final results = <String>[];
    for (var i = 0; i < count; i++) {
      final offset = _u32(bytes, start + 28 + i * 4);
      var position = start + stringsStart + offset;
      if (position >= start + chunkSize) {
        throw const FormatException('String outside pool');
      }
      if (isUtf8) {
        final firstLength = _utf8Length(bytes, position);
        position += firstLength.$2;
        final secondLength = _utf8Length(bytes, position);
        position += secondLength.$2;
        final byteLength = secondLength.$1;
        if (byteLength > 1048576 ||
            position + byteLength >= start + chunkSize) {
          throw const FormatException('String too large');
        }
        results.add(utf8.decode(
          bytes.sublist(position, position + byteLength),
          allowMalformed: true,
        ));
      } else {
        final length = _utf16Length(bytes, position);
        position += length.$2;
        if (length.$1 > 524288 ||
            position + length.$1 * 2 >= start + chunkSize) {
          throw const FormatException('String too large');
        }
        final units = List<int>.generate(
          length.$1,
          (j) => _u16(bytes, position + j * 2),
        );
        results.add(String.fromCharCodes(units));
      }
    }
    return results;
  }

  static (int, int) _utf8Length(Uint8List b, int off) {
    final first = b[off];
    return first & 0x80 == 0
        ? (first, 1)
        : (((first & 0x7f) << 8) | b[off + 1], 2);
  }

  static (int, int) _utf16Length(Uint8List b, int off) {
    final first = _u16(b, off);
    return first & 0x8000 == 0
        ? (first, 2)
        : (((first & 0x7fff) << 16) | _u16(b, off + 2), 4);
  }

  static String _fromPool(List<String> pool, int index) =>
      index >= 0 && index < pool.length ? pool[index] : '';

  static String _typedValue(List<String> pool, int type, int value) {
    switch (type) {
      case 0x03:
        return _fromPool(pool, value);
      case 0x10:
        return value.toString();
      case 0x11:
      case 0x01:
        return '0x${value.toRadixString(16)}';
      case 0x12:
        return value == 0 ? 'false' : 'true';
      default:
        return value.toString();
    }
  }

  static int _u16(Uint8List b, int offset) =>
      ByteData.sublistView(b).getUint16(offset, Endian.little);

  static int _u32(Uint8List b, int offset) =>
      ByteData.sublistView(b).getUint32(offset, Endian.little);
}
