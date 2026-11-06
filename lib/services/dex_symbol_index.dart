import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Resolves DEX pool references without loading a Java decompiler.
/// Every pool access is bounds-checked against the original DEX byte array.
class DexSymbolIndex {
  DexSymbolIndex(this.bytes) : data = ByteData.sublistView(bytes) {
    if (bytes.length < 112 || bytes.length > 32 * 1024 * 1024 ||
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'dex\n' ||
        u32(32) != bytes.length || u32(40) != 0x12345678) {
      throw const FormatException('Invalid DEX symbol table header');
    }
    final strings = table(56, 60, 4);
    stringCount = strings.$1;
    stringsOffset = strings.$2;
    final types = table(64, 68, 4);
    typeCount = types.$1;
    typesOffset = types.$2;
    final protos = table(72, 76, 12);
    protoCount = protos.$1;
    protosOffset = protos.$2;
    final fields = table(80, 84, 8);
    fieldCount = fields.$1;
    fieldsOffset = fields.$2;
    final methods = table(88, 92, 8);
    methodCount = methods.$1;
    methodsOffset = methods.$2;
  }

  final Uint8List bytes;
  final ByteData data;
  late final int stringCount;
  late final int stringsOffset;
  late final int typeCount;
  late final int typesOffset;
  late final int protoCount;
  late final int protosOffset;
  late final int fieldCount;
  late final int fieldsOffset;
  late final int methodCount;
  late final int methodsOffset;
  final Map<int, String> _strings = {};

  void check(int at, int count) {
    if (at < 0 || count < 0 || at > bytes.length || count > bytes.length - at) {
      throw const FormatException('DEX symbol is outside file bounds');
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

  (int, int) table(int sizeAt, int offsetAt, int stride) {
    final count = u32(sizeAt);
    final offset = u32(offsetAt);
    if (count > 500000 || (count == 0 && offset != 0) ||
        (count != 0 && offset == 0)) {
      throw const FormatException('Invalid DEX symbol table dimensions');
    }
    check(offset, count * stride);
    return (count, offset);
  }

  String stringAt(int index) {
    if (index < 0 || index >= stringCount) {
      throw const FormatException('Invalid DEX string index');
    }
    return _strings.putIfAbsent(index, () {
      var at = u32(stringsOffset + index * 4);
      // Skip ULEB128 UTF-16 length, with a strict five-byte maximum.
      var complete = false;
      for (var i = 0; i < 5; i++) {
        check(at, 1);
        final b = bytes[at++];
        if (b & 0x80 == 0) {
          complete = true;
          break;
        }
      }
      if (!complete) throw const FormatException('Invalid DEX string length');
      final start = at;
      while (at < bytes.length && bytes[at] != 0 && at - start <= 8192) {
        at++;
      }
      if (at >= bytes.length || at - start > 8192) {
        throw const FormatException('Unterminated DEX string');
      }
      // Most descriptors are ASCII; modified UTF-8 edge cases may be lossy.
      return utf8.decode(bytes.sublist(start, at), allowMalformed: true);
    });
  }

  String typeAt(int index) {
    if (index < 0 || index >= typeCount) {
      throw const FormatException('Invalid DEX type index');
    }
    return stringAt(u32(typesOffset + index * 4));
  }

  String protoAt(int index) {
    if (index < 0 || index >= protoCount) {
      throw const FormatException('Invalid DEX prototype index');
    }
    final at = protosOffset + index * 12;
    final result = typeAt(u32(at + 4));
    final paramsOff = u32(at + 8);
    final params = StringBuffer();
    if (paramsOff != 0) {
      final count = u32(paramsOff);
      if (count > 255) throw const FormatException('DEX parameter list too long');
      check(paramsOff + 4, count * 2);
      for (var i = 0; i < count; i++) {
        params.write(typeAt(u16(paramsOff + 4 + 2 * i)));
      }
    }
    return '($params)$result';
  }

  String fieldAt(int index) {
    if (index < 0 || index >= fieldCount) {
      throw const FormatException('Invalid DEX field index');
    }
    final at = fieldsOffset + index * 8;
    return '${typeAt(u16(at))}->${stringAt(u32(at + 4))}:'
        '${typeAt(u16(at + 2))}';
  }

  String methodAt(int index) {
    if (index < 0 || index >= methodCount) {
      throw const FormatException('Invalid DEX method index');
    }
    final at = methodsOffset + index * 8;
    return '${typeAt(u16(at))}->${stringAt(u32(at + 4))}'
        '${protoAt(u16(at + 2))}';
  }

  String resolve(String kind, int index) {
    try {
      return switch (kind) {
        'string' => '"${stringAt(index).replaceAll('\n', r'\n')}"',
        'type' => typeAt(index),
        'proto' => protoAt(index),
        'field' => fieldAt(index),
        'method' => methodAt(index),
        // Call sites and method handles require more complex sections.
        _ => '$kind@$index',
      };
    } on FormatException {
      return '$kind@$index';
    }
  }
}
