import 'dart:typed_data';

import 'dex_symbol_index.dart';

/// Read-only, bounded previews of DEX encoded_value items in annotations.
/// Numeric payloads are strings to avoid losing 64-bit precision in JSON.
/// References are symbolic DEX pool identifiers, never executed or evaluated.
class DexDecodedAnnotationElements {
  const DexDecodedAnnotationElements(this.elements, this.complete);

  final List<Map<String, Object?>> elements;
  final bool complete;
}

class _Cursor {
  _Cursor(this.at);
  int at;
}

/// DEX encoded_value decoder with per-annotation depth, element and byte caps.
/// Malformed nested structures are rejected instead of inventing values.
class DexAnnotationValueReader {
  DexAnnotationValueReader(this.bytes, this.symbols);

  final Uint8List bytes;
  final DexSymbolIndex symbols;

  static const maxElements = 16;
  static const maxNestedItems = 16;
  static const maxDepth = 4;
  static const maxValueNodes = 128;
  static const maxEncodedBytes = 8192;

  late int _start;
  int _nodes = 0;

  void _check(_Cursor cursor, int size) {
    symbols.check(cursor.at, size);
    if (cursor.at - _start > maxEncodedBytes - size) {
      throw const FormatException('Annotation encoded value byte limit');
    }
  }

  int _byte(_Cursor cursor) {
    _check(cursor, 1);
    return bytes[cursor.at++];
  }

  int _uleb(_Cursor cursor) {
    var value = 0;
    for (var i = 0; i < 5; i++) {
      final b = _byte(cursor);
      if (i == 4 && (b & 0xf0) != 0) {
        throw const FormatException('Invalid annotation ULEB128');
      }
      value |= (b & 0x7f) << (7 * i);
      if (b & 0x80 == 0) return value;
    }
    throw const FormatException('Annotation ULEB128 too long');
  }

  BigInt _integer(_Cursor cursor, int size, int allowed,
      {bool signed = false}) {
    if (size > allowed) {
      throw const FormatException('Invalid encoded value width');
    }
    _check(cursor, size);
    var number = BigInt.zero;
    for (var i = 0; i < size; i++) {
      number |= BigInt.from(bytes[cursor.at++]) << (i * 8);
    }
    if (signed && (number & (BigInt.one << (size * 8 - 1))) != BigInt.zero) {
      number -= BigInt.one << (size * 8);
    }
    return number;
  }

  String _float(_Cursor cursor, int size, int allowed) {
    if (size > allowed) {
      throw const FormatException('Invalid encoded float width');
    }
    _check(cursor, size);
    final buffer = ByteData(allowed);
    // DEX stores the high-order nonzero bytes, in little-endian order.
    for (var i = 0; i < size; i++) {
      buffer.setUint8(allowed - size + i, bytes[cursor.at++]);
    }
    return (allowed == 4
        ? buffer.getFloat32(0, Endian.little)
        : buffer.getFloat64(0, Endian.little)).toString();
  }

  Map<String, Object?> _value(_Cursor cursor, int depth) {
    if (depth > maxDepth || ++_nodes > maxValueNodes) {
      throw const FormatException('Annotation nesting or value count limit');
    }
    final header = _byte(cursor);
    final type = header & 0x1f;
    final arg = header >> 5;
    final size = arg + 1;

    Map<String, Object?> scalar(String kind, Object? value) =>
        {'kind': kind, 'value': value};
    int index(int maxSize) =>
        _integer(cursor, size, maxSize).toInt();

    switch (type) {
      case 0x00: // VALUE_BYTE
        if (arg != 0) {
          throw const FormatException('Invalid encoded byte width');
        }
        return scalar('byte', _integer(cursor, size, 1, signed: true).toString());
      case 0x02:
        return scalar('short', _integer(cursor, size, 2, signed: true).toString());
      case 0x03:
        return scalar('charCode', _integer(cursor, size, 2).toInt());
      case 0x04:
        return scalar('int', _integer(cursor, size, 4, signed: true).toString());
      case 0x06:
        return scalar('long', _integer(cursor, size, 8, signed: true).toString());
      case 0x10:
        return scalar('float', _float(cursor, size, 4));
      case 0x11:
        return scalar('double', _float(cursor, size, 8));
      case 0x15:
        final id = index(4);
        return {'kind': 'methodType', 'index': id,
          'prototype': symbols.protoAt(id)};
      case 0x16:
        // Method handle pool is not indexed by DexSymbolIndex.
        return {'kind': 'methodHandle', 'index': index(4),
          'resolved': false};
      case 0x17:
        final id = index(4);
        return {'kind': 'string', 'index': id,
          'value': symbols.stringAt(id)};
      case 0x18:
        final id = index(4);
        return {'kind': 'type', 'index': id,
          'descriptor': symbols.typeAt(id)};
      case 0x19:
      case 0x1b:
        final id = index(4);
        return {'kind': type == 0x19 ? 'field' : 'enum', 'index': id,
          'descriptor': symbols.fieldAt(id)};
      case 0x1a:
        final id = index(4);
        return {'kind': 'method', 'index': id,
          'descriptor': symbols.methodAt(id)};
      case 0x1c: // VALUE_ARRAY
        if (arg != 0) {
          throw const FormatException('Array must have zero value_arg');
        }
        final count = _uleb(cursor);
        if (count > maxNestedItems) {
          throw const FormatException('Nested annotation array too large');
        }
        return {'kind': 'array', 'items': [
          for (var i = 0; i < count; i++) _value(cursor, depth + 1),
        ]};
      case 0x1d: // VALUE_ANNOTATION
        if (arg != 0) {
          throw const FormatException('Annotation must have zero value_arg');
        }
        final descriptor = symbols.typeAt(_uleb(cursor));
        final count = _uleb(cursor);
        if (count > maxNestedItems) {
          throw const FormatException('Nested annotation has too many items');
        }
        return {'kind': 'annotation', 'type': descriptor, 'elements': [
          for (var i = 0; i < count; i++)
            {'name': symbols.stringAt(_uleb(cursor)),
             'value': _value(cursor, depth + 1)},
        ]};
      case 0x1e:
        if (arg != 0) {
          throw const FormatException('Null must have zero value_arg');
        }
        return scalar('null', null);
      case 0x1f:
        if (arg > 1) {
          throw const FormatException('Invalid encoded boolean');
        }
        return scalar('boolean', arg == 1);
      default:
        throw FormatException('Unsupported DEX encoded value 0x${type.toRadixString(16)}');
    }
  }

  DexDecodedAnnotationElements decodeElements(int offset, int declaredCount) {
    if (declaredCount < 0 || declaredCount > 65535) {
      throw const FormatException('Invalid annotation element count');
    }
    _start = offset;
    _nodes = 0;
    final cursor = _Cursor(offset);
    final output = <Map<String, Object?>>[];
    final take = declaredCount < maxElements ? declaredCount : maxElements;
    for (var i = 0; i < take; i++) {
      final name = symbols.stringAt(_uleb(cursor));
      output.add({'name': name, 'value': _value(cursor, 0)});
    }
    return DexDecodedAnnotationElements(
      List<Map<String, Object?>>.unmodifiable(output),
      declaredCount <= maxElements,
    );
  }
}
