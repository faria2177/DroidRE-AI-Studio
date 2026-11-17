import 'dart:convert';
import 'dart:typed_data';

/// Classic 27/29 metadata definition rows. Native registration is separate.
class Il2cppMetadataMapping {
  const Il2cppMetadataMapping._();
  static const headerSize = 256;
  static const typeStride = 88;
  static const methodStride = 32;

  static Map<String, Object?> inspect(Uint8List bytes) {
    if (bytes.length < headerSize || bytes.length > 32 * 1024 * 1024) {
      throw const FormatException('Invalid classic metadata size');
    }
    final data = ByteData.sublistView(bytes);
    int u32(int at) => data.getUint32(at, Endian.little);
    int i32(int at) => data.getInt32(at, Endian.little);
    int u16(int at) => data.getUint16(at, Endian.little);
    if (u32(0) != 0xfab11baf || !const {27, 29}.contains(u32(4))) {
      throw const FormatException('Only classic metadata versions 27/29 are mapped');
    }
    final spans = <(int, int)>[];
    final ranges = <(int, int)>[];
    for (var i = 0; i < 31; i++) {
      final start = u32(8 + i * 8), size = u32(12 + i * 8);
      if (start > bytes.length || size > bytes.length - start ||
          (size > 0 && start < headerSize)) {
        throw const FormatException('Metadata section outside classic file');
      }
      if (size > 0) {
        if (spans.any((s) => start < s.$2 && s.$1 < start + size)) {
          throw const FormatException('Overlapping metadata sections');
        }
        spans.add((start, start + size));
      }
      ranges.add((start, size));
    }
    final (strings, stringBytes) = ranges[2];
    final (methods, methodBytes) = ranges[5];
    final (types, typeBytes) = ranges[19];
    if (stringBytes == 0 || typeBytes % typeStride != 0 ||
        methodBytes % methodStride != 0) {
      throw const FormatException('Classic definition table stride mismatch');
    }
    final typeCount = typeBytes ~/ typeStride, methodCount = methodBytes ~/ methodStride;
    String? resolve(int index) {
      if (index >= stringBytes) {
        return null;
      }
      final start = strings + index;
      final limit = (start + 513).clamp(start, strings + stringBytes).toInt();
      var end = start;
      while (end < limit && bytes[end] != 0) {
        end++;
      }
      if (end == limit) {
        return null;
      }
      try {
        return utf8.decode(bytes.sublist(start, end));
      } on FormatException {
        return null;
      }
    }
    Map<String, Object?>? typeRow(int index) {
      if (index < 0 || index >= typeCount) {
        return null;
      }
      final at = types + index * typeStride;
      final name = resolve(u32(at)), namespace = resolve(u32(at + 4));
      final token = u32(at + 84);
      final first = i32(at + 36), count = u16(at + 64);
      if (name == null || name.isEmpty || namespace == null ||
          token >> 24 != 2 || (token & 0xffffff) == 0 ||
          (count > 0 && (first < 0 || first >= methodCount || count > methodCount - first))) {
        return null;
      }
      return {'index': index, 'name': name, 'namespace': namespace,
        'token': '0x${token.toRadixString(16)}', 'methodStart': first, 'methodCount': count,
        'flags': u32(at + 28)};
    }
    final typeRows = <Map<String, Object?>>[];
    var invalidTypes = 0;
    for (var i = 0; i < typeCount && i < 200; i++) {
      final row = typeRow(i);
      if (row == null) {
        invalidTypes++;
      } else {
        typeRows.add(row);
      }
    }
    final methodRows = <Map<String, Object?>>[];
    var invalidMethods = 0;
    for (var i = 0; i < methodCount && i < 300; i++) {
      final at = methods + i * methodStride;
      final name = resolve(u32(at));
      final ownerIndex = i32(at + 4);
      final owner = typeRow(ownerIndex);
      final token = u32(at + 20);
      if (name == null || name.isEmpty || owner == null ||
          token >> 24 != 6 || (token & 0xffffff) == 0 ||
          i < (owner['methodStart'] as int) ||
          i - (owner['methodStart'] as int) >= (owner['methodCount'] as int)) {
        invalidMethods++;
        continue;
      }
      methodRows.add({'index': i, 'name': name, 'declaringTypeIndex': ownerIndex,
        'declaringType': owner['name'], 'namespace': owner['namespace'],
        'token': '0x${token.toRadixString(16)}',
        'returnTypeIndex': i32(at + 8), 'parameterCount': u16(at + 30),
        'flags': u16(at + 24)});
    }
    return {'version': u32(4), 'declaredTypes': typeCount,
      'declaredMethods': methodCount, 'types': typeRows, 'methods': methodRows,
      'invalidSampledTypes': invalidTypes, 'invalidSampledMethods': invalidMethods,
      'partial': true,
      'note': 'Classic metadata table evidence, no native address mapping, method body or original C#.'};
  }
}
