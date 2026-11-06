import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
class DecodedAndroidXml {
  const DecodedAndroidXml({
    required this.xml,
    required this.elements,
    required this.attributes,
  });

  final String xml;
  final int elements;
  final int attributes;
}

/// Read-only Android AXML (RES_XML_TYPE) tree viewer.
/// Resource IDs are kept symbolic: resources.arsc value resolution is separate.
class AndroidBinaryXmlDecoder {
  const AndroidBinaryXmlDecoder._();

  static const maxBytes = 2 * 1024 * 1024;
  static const _none = 0xffffffff;

  static DecodedAndroidXml decode(Uint8List bytes) {
    if (bytes.length < 8 || bytes.length > maxBytes) {
      throw const FormatException('XML is missing or exceeds 2 MiB limit');
    }
    if (utf8.decode(bytes.take(48).toList(), allowMalformed: true)
        .trimLeft().startsWith('<')) {
      return DecodedAndroidXml(
        xml: utf8.decode(bytes, allowMalformed: true),
        elements: 0,
        attributes: 0,
      );
    }
    final data = ByteData.sublistView(bytes);
    void check(int at, int length, [int? end]) {
      final stop = end ?? bytes.length;
      if (at < 0 || length < 0 || at > stop ||
          length > stop - at || stop > bytes.length) {
        throw const FormatException('Truncated binary XML structure');
      }
    }

    int u16(int at) {
      check(at, 2);
      return data.getUint16(at, Endian.little);
    }

    int u32(int at) {
      check(at, 4);
      return data.getUint32(at, Endian.little);
    }

    (int, int) utf8Length(int offset, int end) {
      check(offset, 1, end);
      final first = bytes[offset];
      if (first & 0x80 == 0) return (first, offset + 1);
      check(offset, 2, end);
      return (((first & 0x7f) << 8) | bytes[offset + 1], offset + 2);
    }

    (int, int) utf16Length(int offset, int end) {
      check(offset, 2, end);
      final first = u16(offset);
      if (first & 0x8000 == 0) return (first, offset + 2);
      check(offset, 4, end);
      return (((first & 0x7fff) << 16) | u16(offset + 2), offset + 4);
    }

    List<String> stringPool(int start, int end) {
      check(start, 28, end);
      final count = u32(start + 8);
      final flags = u32(start + 16);
      final dataStart = u32(start + 20);
      if (count > 100000) {
        throw const FormatException('Too many Android XML strings');
      }
      check(start + 28, count * 4, end);
      final result = <String>[];
      for (var i = 0; i < count; i++) {
        var at = start + dataStart + u32(start + 28 + i * 4);
        check(at, 1, end);
        if (flags & 0x100 != 0) {
          final first = utf8Length(at, end);
          final second = utf8Length(first.$2, end);
          at = second.$2;
          final length = second.$1;
          if (length > 8192) {
            throw const FormatException('XML text exceeds per-string limit');
          }
          check(at, length + 1, end);
          if (bytes[at + length] != 0) {
            throw const FormatException('Unterminated Android XML string');
          }
          result.add(utf8.decode(bytes.sublist(at, at + length),
              allowMalformed: true));
        } else {
          final size = utf16Length(at, end);
          if (size.$1 > 8192) {
            throw const FormatException('XML text exceeds per-string limit');
          }
          check(size.$2, size.$1 * 2 + 2, end);
          final units = List<int>.generate(
            size.$1, (j) => u16(size.$2 + j * 2),
          );
          result.add(String.fromCharCodes(units));
        }
      }
      return result;
    }

    String escape(String value) => value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');

    final strings = <String>[];
    String fromPool(int index) {
      if (index == _none) return '';
      if (index >= strings.length) {
        throw const FormatException('Invalid Android XML string reference');
      }
      return strings[index];
    }

    String typed(int type, int value) => switch (type) {
      0x03 => fromPool(value),
      0x01 => '@0x${value.toRadixString(16).padLeft(8, '0')}',
      0x02 => '?0x${value.toRadixString(16).padLeft(8, '0')}',
      0x10 => value.toSigned(32).toString(),
      0x11 => '0x${value.toRadixString(16)}',
      0x12 => value == 0 ? 'false' : 'true',
      >= 0x1c && <= 0x1f => '#${value.toRadixString(16).padLeft(8, '0')}',
      _ => '(type 0x${type.toRadixString(16)}:0x${value.toRadixString(16)})',
    };

    if (u16(0) != 0x0003 || u16(2) < 8 || u32(4) != bytes.length) {
      throw const FormatException('Not a supported Android binary XML document');
    }
    final buffer = StringBuffer();
    final namespaces = <int, String>{};
    final tags = <String>[];
    var elements = 0;
    var attributes = 0;
    var cursor = u16(2);
    var chunks = 0;
    while (cursor < bytes.length) {
      check(cursor, 8);
      final type = u16(cursor);
      final header = u16(cursor + 2);
      final size = u32(cursor + 4);
      if (header < 8 || size < header || size == 0) {
        throw const FormatException('Invalid Android XML chunk');
      }
      check(cursor, size);
      final end = cursor + size;
      if (chunks++ > 150000) {
        throw const FormatException('Too many Android XML chunks');
      }
      if (type == 0x0001) {
        strings
          ..clear()
          ..addAll(stringPool(cursor, end));
      } else if (type == 0x0100) {
        check(cursor + 16, 8, end);
        namespaces[u32(cursor + 20)] = fromPool(u32(cursor + 16));
      } else if (type == 0x0101) {
        check(cursor + 16, 8, end);
        namespaces.remove(u32(cursor + 20));
      } else if (type == 0x0102) {
        check(cursor + 16, 20, end);
        final ns = u32(cursor + 16);
        final name = fromPool(u32(cursor + 20));
        final prefix = namespaces[ns];
        final tag = prefix == null || prefix.isEmpty ? name : '$prefix:$name';
        final attrStart = u16(cursor + 24);
        final attrSize = u16(cursor + 26);
        final count = u16(cursor + 28);
        if (tag.isEmpty || tags.length >= 256 || elements >= 10000 ||
            count > 2048 || attrStart < 20 || attrSize < 20) {
          throw const FormatException('Invalid Android XML element');
        }
        final attrOffset = cursor + 16 + attrStart;
        check(attrOffset, count * attrSize, end);
        buffer.write('${List.filled(tags.length, '  ').join()}<$tag');
        if (tags.isEmpty) {
          for (final item in namespaces.entries) {
            final uri = fromPool(item.key);
            final part = item.value.isEmpty ? '' : ':${item.value}';
            buffer.write(' xmlns$part="${escape(uri)}"');
          }
        }
        for (var j = 0; j < count; j++) {
          final at = attrOffset + j * attrSize;
          final attrNs = u32(at);
          final attrName = fromPool(u32(at + 4));
          final qualified = namespaces[attrNs] == null || namespaces[attrNs]!.isEmpty
              ? attrName : '${namespaces[attrNs]}:$attrName';
          final raw = u32(at + 8);
          final value = raw == _none
              ? typed(bytes[at + 15], u32(at + 16))
              : fromPool(raw);
          buffer.write(' $qualified="${escape(value)}"');
          if (++attributes > 50000) {
            throw const FormatException('Too many XML attributes');
          }
        }
        buffer.writeln('>');
        tags.add(tag);
        elements++;
      } else if (type == 0x0103) {
        check(cursor + 16, 8, end);
        final name = fromPool(u32(cursor + 20));
        if (tags.isEmpty || !tags.last.endsWith(name)) {
          throw const FormatException('Unbalanced Android XML elements');
        }
        final tag = tags.removeLast();
        buffer.writeln('${List.filled(tags.length, '  ').join()}</$tag>');
      } else if (type == 0x0104) {
        check(cursor + 16, 12, end);
        final value = fromPool(u32(cursor + 16));
        buffer.writeln('${List.filled(tags.length, '  ').join()}${escape(value)}');
      }
      cursor = end;
    }
    if (tags.isNotEmpty || elements == 0) {
      throw const FormatException('Android XML tree is incomplete');
    }
    return DecodedAndroidXml(
      xml: buffer.toString(),
      elements: elements,
      attributes: attributes,
    );
  }
}
