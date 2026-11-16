import 'dart:convert';
import 'package:flutter/foundation.dart';

@immutable
class ArscValue {
  const ArscValue(this.id, this.name, this.value, this.config,
      {this.dataType, this.rawData});
  final int id;
  final String name;
  final String value;
  final int config;
  /// Original Android Res_value type and data (not a resolved reference).
  final int? dataType;
  final int? rawData;
  String get idHex => '0x${id.toRadixString(16).padLeft(8, '0')}';
}

@immutable
class ArscValueReport {
  const ArscValueReport(this.values, this.scannedSlots, this.truncated,
      this.warnings);
  final List<ArscValue> values;
  final int scannedSlots;
  final bool truncated;
  final List<String> warnings;
}

class _Reader {
  _Reader(this.bytes) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData data;

  void check(int offset, int size, [int? end]) {
    final bound = end ?? bytes.length;
    if (offset < 0 || size < 0 || bound > bytes.length ||
        offset > bound || size > bound - offset) {
      throw const FormatException('ARSC offset is outside chunk');
    }
  }

  int u8(int at) { check(at, 1); return bytes[at]; }
  int u16(int at) { check(at, 2); return data.getUint16(at, Endian.little); }
  int u32(int at) { check(at, 4); return data.getUint32(at, Endian.little); }

  _Chunk chunk(int at, int bound) {
    check(at, 8, bound);
    final header = u16(at + 2);
    final size = u32(at + 4);
    if (header < 8 || size < header) {
      throw const FormatException('Invalid ARSC chunk size');
    }
    check(at, size, bound);
    return _Chunk(at, size, header, u16(at));
  }
}

class _Chunk {
  const _Chunk(this.start, this.size, this.header, this.type);
  final int start, size, header, type;
  int get end => start + size;
}

class _Pool {
  _Pool(this.r, this.chunk) {
    if (chunk.type != 1 || chunk.header < 28) {
      throw const FormatException('Invalid ARSC string pool');
    }
    count = r.u32(chunk.start + 8);
    utf8Strings = (r.u32(chunk.start + 16) & 0x100) != 0;
    stringsStart = r.u32(chunk.start + 20);
    if (count > 200000 || chunk.header + count * 4 > chunk.size ||
        stringsStart < chunk.header + count * 4 ||
        stringsStart > chunk.size) {
      throw const FormatException('Invalid ARSC string pool offsets');
    }
  }
  final _Reader r;
  final _Chunk chunk;
  late final int count, stringsStart;
  late final bool utf8Strings;
  final Map<int, String> cache = {};

  String at(int index) {
    if (index < 0 || index >= count) {
      throw const FormatException('Invalid ARSC string index');
    }
    return cache.putIfAbsent(index, () {
      final off = r.u32(chunk.start + chunk.header + index * 4);
      var cursor = chunk.start + stringsStart + off;
      int read8() {
        r.check(cursor, 1, chunk.end);
        return r.u8(cursor++);
      }
      int read16() {
        r.check(cursor, 2, chunk.end);
        final n = r.u16(cursor);
        cursor += 2;
        return n;
      }
      int utf8Len() {
        final n = read8();
        return (n & 0x80) == 0 ? n : ((n & 0x7f) << 8) | read8();
      }
      int utf16Len() {
        final n = read16();
        return (n & 0x8000) == 0 ? n :
            ((n & 0x7fff) << 16) | read16();
      }
      if (utf8Strings) {
        utf8Len(); // UTF-16 character count.
        final countBytes = utf8Len();
        if (countBytes > 8192) {
          throw const FormatException('ARSC UTF-8 string too long');
        }
        r.check(cursor, countBytes + 1, chunk.end);
        if (r.u8(cursor + countBytes) != 0) {
          throw const FormatException('ARSC UTF-8 terminator missing');
        }
        try {
          return utf8.decode(r.bytes.sublist(cursor, cursor + countBytes));
        } on FormatException {
          throw const FormatException('Invalid ARSC UTF-8');
        }
      }
      final units = utf16Len();
      if (units > 4096) {
        throw const FormatException('ARSC UTF-16 string too long');
      }
      r.check(cursor, units * 2 + 2, chunk.end);
      if (r.u16(cursor + units * 2) != 0) {
        throw const FormatException('ARSC UTF-16 terminator missing');
      }
      return String.fromCharCodes([
        for (var i = 0; i < units; i++) r.u16(cursor + 2 * i),
      ]);
    });
  }
}

/// Read-only extraction of simple compiled resource values. Complex bags,
/// overlay mappings, and configuration selection are not resolved.
class ArscValueReader {
  const ArscValueReader._();
  static const maxResults = 250;
  static const maxScannedSlots = 200000;

  static ArscValueReport parse(Uint8List bytes, {
    int resultLimit = maxResults,
    int scanLimit = maxScannedSlots,
  }) {
    if (bytes.length < 12 || bytes.length > 40 * 1024 * 1024 ||
        resultLimit < 1 || resultLimit > maxResults ||
        scanLimit < 1 || scanLimit > maxScannedSlots) {
      throw const FormatException('Invalid ARSC input or scan limits');
    }
    final r = _Reader(bytes);
    final root = r.chunk(0, bytes.length);
    if (root.type != 2 || root.header < 12 || root.end != bytes.length) {
      throw const FormatException('Not an Android resource table');
    }
    _Pool? global;
    final packages = <_Chunk>[];
    var cursor = root.header;
    while (cursor < root.end) {
      final chunk = r.chunk(cursor, root.end);
      if (chunk.type == 1 && chunk.header >= 28) {
        global ??= _Pool(r, chunk);
      } else if (chunk.type == 0x0200) {
        packages.add(chunk);
      }
      cursor = chunk.end;
    }

    final values = <ArscValue>[];
    final warnings = <String>[];
    var scanned = 0;
    var config = 0;
    var truncated = false;
    void warn(String message) {
      if (warnings.length < 20 && !warnings.contains(message)) {
        warnings.add(message);
      }
    }

    for (final pkg in packages) {
      if (pkg.header < 284) {
        warn('Package lacks type/key pool offsets');
        continue;
      }
      final packageId = r.u32(pkg.start + 8);
      final typeIdOffset = pkg.header >= 288 ? r.u32(pkg.start + 284) : 0;
      if (packageId < 1 || packageId > 255) {
        warn('Unsupported package identifier');
        continue;
      }
      _Pool? nestedPool(int relative) {
        if (relative == 0 || relative > pkg.size - 8) return null;
        final child = r.chunk(pkg.start + relative, pkg.end);
        return child.type == 1 && child.header >= 28 ?
            _Pool(r, child) : null;
      }
      final typePool = nestedPool(r.u32(pkg.start + 268));
      final keyPool = nestedPool(r.u32(pkg.start + 276));
      if (typePool == null || keyPool == null) {
        warn('Package type/key pools unavailable');
        continue;
      }
      var at = pkg.start + pkg.header;
      while (at < pkg.end) {
        final chunk = r.chunk(at, pkg.end);
        at = chunk.end;
        if (chunk.type != 0x0201) continue;
        config++;
        if (chunk.header < 24) {
          throw const FormatException('Invalid resource type header');
        }
        final typeId = r.u8(chunk.start + 8);
        final flags = r.u8(chunk.start + 9);
        final count = r.u32(chunk.start + 12);
        final entriesStart = r.u32(chunk.start + 16);
        if (typeId == 0 || typeId + typeIdOffset > 255 ||
            count > 65536 || (flags & ~3) != 0) {
          warn('Unsupported resource type configuration');
          continue;
        }
        final sparse = (flags & 1) != 0;
        final offset16 = (flags & 2) != 0;
        final stride = sparse ? 4 : (offset16 ? 2 : 4);
        if (entriesStart > chunk.size ||
            chunk.header + count * stride > entriesStart) {
          throw const FormatException('ARSC entry index overlaps entries');
        }
        final typeName = typePool.at(typeId - 1);
        for (var i = 0; i < count; i++) {
          if (scanned >= scanLimit || values.length >= resultLimit) {
            truncated = true;
            break;
          }
          scanned++;
          final indexAt = chunk.start + chunk.header + i * stride;
          final entryId = sparse ? r.u16(indexAt) : i;
          final offset = sparse
              ? r.u16(indexAt + 2) * 4
              : offset16
                  ? (r.u16(indexAt) == 0xffff ? 0xffffffff :
                      r.u16(indexAt) * 4)
                  : r.u32(indexAt);
          if (offset == 0xffffffff) continue;
          final entry = chunk.start + entriesStart + offset;
          r.check(entry, 8, chunk.end);
          final entrySize = r.u16(entry);
          final entryFlags = r.u16(entry + 2);
          if (entrySize < 8) {
            throw const FormatException('ARSC entry header invalid');
          }
          r.check(entry, entrySize, chunk.end);
          if ((entryFlags & 1) != 0) {
            warn('Complex bag/map entries skipped');
            continue;
          }
          final key = keyPool.at(r.u32(entry + 4));
          final valueAt = entry + entrySize;
          r.check(valueAt, 8, chunk.end);
          if (r.u16(valueAt) < 8) {
            throw const FormatException('ARSC value header invalid');
          }
          final kind = r.u8(valueAt + 3);
          final data = r.u32(valueAt + 4);
          final value = switch (kind) {
            0x00 => 'null',
            0x01 => '@0x${data.toRadixString(16).padLeft(8, '0')}',
            0x02 => '?0x${data.toRadixString(16).padLeft(8, '0')}',
            0x03 => global?.at(data) ?? 'string@$data (unresolved)',
            0x04 => r.data.getFloat32(valueAt + 4, Endian.little).toString(),
            0x05 || 0x06 => 'complex:0x${data.toRadixString(16)}',
            0x10 => data.toSigned(32).toString(),
            0x11 => '0x${data.toRadixString(16)}',
            0x12 => data == 0 ? 'false' : 'true',
            >= 0x1c && <= 0x1f => '#${data.toRadixString(16).padLeft(8, '0')}',
            _ => 'type:0x${kind.toRadixString(16)} raw:0x${data.toRadixString(16)}',
          };
          values.add(ArscValue(
            (packageId << 24) | ((typeId + typeIdOffset) << 16) | entryId,
            '@$typeName/$key',
            value,
            config,
            dataType: kind,
            rawData: data,
          ));
        }
        if (truncated) break;
      }
      if (truncated) break;
    }
    return ArscValueReport(values, scanned, truncated, warnings);
  }
}
