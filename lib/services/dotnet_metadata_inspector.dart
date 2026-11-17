import 'dart:convert';
import 'dart:typed_data';

/// ECMA-335 metadata root/stream inventory, not a full table row decoder.
class DotnetMetadataInspector {
  const DotnetMetadataInspector._();

  static const tableNames = <int, String>{
    0: 'Module', 1: 'TypeRef', 2: 'TypeDef', 4: 'Field', 6: 'MethodDef',
    8: 'Param', 9: 'InterfaceImpl', 10: 'MemberRef', 12: 'CustomAttribute',
    17: 'StandAloneSig', 20: 'Event', 23: 'Property', 26: 'ModuleRef',
    32: 'Assembly', 35: 'AssemblyRef', 38: 'File', 39: 'ExportedType',
    40: 'ManifestResource', 42: 'GenericParam', 43: 'MethodSpec',
  };

  static Map<String, Object?> inspect(Uint8List bytes, int offset, int size) {
    if (offset < 0 || size < 20 || offset > bytes.length ||
        size > bytes.length - offset) {
      throw const FormatException('Metadata root outside file');
    }
    final d = ByteData.sublistView(bytes, offset, offset + size);
    void check(int at, int count) {
      if (at < 0 || count < 0 || at > size || count > size - at) {
        throw const FormatException('Metadata field outside root');
      }
    }
    int u16(int at) {
      check(at, 2);
      return d.getUint16(at, Endian.little);
    }
    int u32(int at) {
      check(at, 4);
      return d.getUint32(at, Endian.little);
    }
    if (u32(0) != 0x424a5342) {
      throw const FormatException('Metadata signature missing');
    }
    final versionLength = u32(12);
    if (versionLength > 256 || versionLength % 4 != 0) {
      throw const FormatException('Unsupported metadata version string length');
    }
    var at = 16 + versionLength;
    check(at, 4);
    final count = u16(at + 2);
    at += 4;
    if (count < 1 || count > 32) {
      throw const FormatException('Unsupported metadata stream count');
    }
    final streams = <Map<String, Object>>[];
    final spans = <(int, int)>[];
    final names = <String>{};
    int? tableStart;
    int? tableSize;
    for (var i = 0; i < count; i++) {
      check(at, 8);
      final start = u32(at);
      final length = u32(at + 4);
      final nameAt = at + 8;
      var end = nameAt;
      while (end < size && end - nameAt < 32 &&
          d.getUint8(end) != 0) {
        end++;
      }
      if (end == nameAt || end >= size || end - nameAt >= 32) {
        throw const FormatException('Invalid metadata stream name');
      }
      final name = ascii.decode(bytes.sublist(offset + nameAt, offset + end),
          allowInvalid: true);
      if (!RegExp(r'^[\x21-\x7e]+$').hasMatch(name) || !names.add(name)) {
        throw const FormatException('Invalid or duplicate metadata stream');
      }
      at = (end + 4) & ~3;
      check(0, at);
      check(start, length);
      if (length > 0) {
        if (spans.any((s) => start < s.$2 && s.$1 < start + length)) {
          throw const FormatException('Overlapping metadata streams');
        }
        spans.add((start, start + length));
      }
      streams.add({'name': name, 'rootOffset': start, 'fileOffset': offset + start,
        'bytes': length});
      if (name == '#~' || name == '#-') {
        if (tableStart != null) {
          throw const FormatException('Multiple metadata table streams');
        }
        tableStart = start;
        tableSize = length;
      }
    }
    if (spans.any((s) => s.$1 < at)) {
      throw const FormatException('Metadata stream overlaps root headers');
    }
    final rows = <Map<String, Object>>[];
    if (tableStart != null && tableSize != null) {
      if (tableSize < 24) {
        throw const FormatException('Truncated metadata table header');
      }
      var cursor = tableStart + 24;
      final low = u32(tableStart + 8);
      final high = u32(tableStart + 12);
      for (var id = 0; id < 64; id++) {
        final mask = id < 32 ? low : high;
        if ((mask & (1 << (id % 32))) == 0) {
          continue;
        }
        if (cursor + 4 > tableStart + tableSize) {
          throw const FormatException('Truncated metadata row counts');
        }
        rows.add({'tableId': id, 'name': tableNames[id] ?? 'Table $id',
          'declaredRows': u32(cursor)});
        cursor += 4;
      }
    }
    return {'status': 'stream-headers-observed', 'streams': streams,
      'tableRowCounts': rows, 'partial': true,
      'note': 'Declared row counts only; no row contents or assembly validity verified.'};
  }
}
