import 'dart:convert';
import 'dart:typed_data';

/// Reads directory evidence from a previously validated PE header.
class PeDirectoryInspector {
  PeDirectoryInspector._(this.bytes, this.header) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final Map<String, Object?> header;
  final ByteData data;
  static const maxLibraries = 128;
  static const maxSymbols = 2048;
  static const maxName = 512;

  static Map<String, Object?> inspect(Uint8List bytes, Map<String, Object?> header) {
    final reader = PeDirectoryInspector._(bytes, header);
    Map<String, Object?> attempt(Map<String, Object?> Function() read) {
      try {
        return read();
      } on FormatException catch (e) {
        return {'status': 'unresolved', 'partial': true, 'warning': e.message};
      }
    }
    return {
      'imports': attempt(reader._imports),
      'exports': attempt(reader._exports),
      'clr': attempt(reader._clr),
      'scope': 'Static standard import/export and CLR header evidence. '
          'No runtime dependency resolution, delay imports, signature verification or IL decompilation.',
    };
  }

  int _u16(int at) => data.getUint16(at, Endian.little);
  int _u32(int at) => data.getUint32(at, Endian.little);
  (int, int)? _directory(int index) {
    for (final row in (header['directories'] as List).whereType<Map>()) {
      if (row['index'] == index) {
        final rva = row['address'] as int;
        final size = row['size'] as int;
        if (rva == 0 && size == 0) {
          return null;
        }
        if (rva == 0 || size == 0 || rva + size > 0x100000000) {
          throw const FormatException('Invalid PE directory range');
        }
        return (rva, size);
      }
    }
    return null;
  }

  /// Deliberately requires a unique file-backed section. Header-only and
  /// zero-filled virtual ranges are unsupported rather than guessed.
  (int, int) _map(int rva, int length) {
    if (rva <= 0 || length <= 0 || rva + length > 0x100000000) {
      throw const FormatException('Invalid RVA range');
    }
    (int, int)? result;
    for (final row in (header['sections'] as List).whereType<Map>()) {
      final start = row['virtualAddress'] as int;
      final rawSize = row['rawSize'] as int;
      final virtualSize = row['virtualSize'] as int;
      final span = virtualSize == 0 ? rawSize :
          (virtualSize < rawSize ? virtualSize : rawSize);
      final delta = rva - start;
      if (delta < 0 || delta >= span) {
        continue;
      }
      if (length > span - delta || result != null) {
        throw const FormatException('Ambiguous or non-contiguous RVA range');
      }
      final offset = (row['rawOffset'] as int) + delta;
      if (offset < 0 || offset > bytes.length || span - delta > bytes.length - offset) {
        throw const FormatException('RVA mapping outside file');
      }
      result = (offset, span - delta);
    }
    if (result == null) {
      throw const FormatException('RVA is not file-backed');
    }
    return result;
  }

  String _name(int rva, {int? bound}) {
    final (offset, available) = _map(rva, 1);
    var length = available.clamp(0, maxName + 1).toInt();
    if (bound != null) {
      length = length.clamp(0, bound).toInt();
    }
    var end = offset;
    while (end < offset + length && bytes[end] != 0) {
      if (bytes[end] < 32 || bytes[end] > 126) {
        throw const FormatException('Non-printable PE name');
      }
      end++;
    }
    if (end == offset || end == offset + length) {
      throw const FormatException('Missing or oversized PE name');
    }
    return ascii.decode(bytes.sublist(offset, end));
  }

  Map<String, Object?> _imports() {
    final directory = _directory(1);
    if (directory == null) {
      return {'status': 'not-declared', 'libraries': [], 'partial': false};
    }
    final (rva, size) = directory;
    final libraries = <Map<String, Object?>>[];
    var total = 0;
    var partial = false;
    var terminated = false;
    final width = header['kind'] == 'PE32+' ? 8 : 4;
    for (var i = 0; i < maxLibraries && (i + 1) * 20 <= size; i++) {
      final at = _map(rva + i * 20, 20).$1;
      final lookup = _u32(at);
      final stamp = _u32(at + 4);
      final forwarder = _u32(at + 8);
      final name = _u32(at + 12);
      final iat = _u32(at + 16);
      if (lookup == 0 && stamp == 0 && forwarder == 0 && name == 0 && iat == 0) {
        terminated = true;
        break;
      }
      if (name == 0 || iat == 0) {
        throw const FormatException('Invalid import descriptor');
      }
      final dll = _name(name);
      final symbols = <Map<String, Object?>>[];
      var thunkEnded = false;
      // An already-bound IAT without lookup data is not a name table.
      if (lookup == 0 && stamp != 0) {
        partial = true;
      } else {
        final table = lookup == 0 ? iat : lookup;
        for (var n = 0; total < maxSymbols; n++) {
          final pos = _map(table + n * width, width).$1;
          final low = _u32(pos);
          final high = width == 8 ? _u32(pos + 4) : 0;
          if (low == 0 && high == 0) {
            thunkEnded = true;
            break;
          }
          final ordinal = width == 8
              ? (high & 0x80000000) != 0 : (low & 0x80000000) != 0;
          if (ordinal) {
            if ((low & (width == 8 ? 0xffff0000 : 0x7fff0000)) != 0 ||
                (width == 8 && high != 0x80000000)) {
              throw const FormatException('Invalid ordinal thunk');
            }
            symbols.add({'ordinal': low & 0xffff});
          } else {
            if (high != 0 || low == 0) {
              throw const FormatException('Invalid import name RVA');
            }
            final hint = _u16(_map(low, 2).$1);
            symbols.add({'name': _name(low + 2), 'hint': hint});
          }
          total++;
        }
        if (!thunkEnded) {
          partial = true;
        }
      }
      libraries.add({'dll': dll, 'symbols': symbols, 'lookupTerminated': thunkEnded});
      if (total >= maxSymbols) {
        break;
      }
    }
    return {'status': 'observed', 'libraries': libraries, 'symbolsRead': total,
      'partial': partial || !terminated};
  }

  Map<String, Object?> _exports() {
    final directory = _directory(0);
    if (directory == null) {
      return {'status': 'not-declared', 'symbols': [], 'partial': false};
    }
    final (rva, size) = directory;
    if (size < 40) {
      throw const FormatException('Truncated export directory');
    }
    final at = _map(rva, 40).$1;
    final dll = _name(_u32(at + 12));
    final base = _u32(at + 16);
    final functionCount = _u32(at + 20);
    final nameCount = _u32(at + 24);
    final functions = _u32(at + 28);
    final names = _u32(at + 32);
    final ordinals = _u32(at + 36);
    if (functionCount > 0xffffffff - base + 1) {
      throw const FormatException('Export ordinal overflow');
    }
    final named = <int, List<String>>{};
    for (var n = 0; n < nameCount && n < maxSymbols; n++) {
      final index = _u16(_map(ordinals + n * 2, 2).$1);
      if (index >= functionCount) {
        throw const FormatException('Export name ordinal outside function table');
      }
      final name = _name(_u32(_map(names + n * 4, 4).$1));
      named.putIfAbsent(index, () => []).add(name);
    }
    final symbols = <Map<String, Object?>>[];
    for (var i = 0; i < functionCount && i < maxSymbols; i++) {
      final address = _u32(_map(functions + i * 4, 4).$1);
      if (address == 0) {
        continue; // Unused export address entry.
      }
      final forwarded = address >= rva && address < rva + size;
      symbols.add({
        'ordinal': base + i, 'names': named[i] ?? const <String>[],
        'rva': address,
        if (forwarded) 'forwarder': _name(address, bound: rva + size - address),
      });
    }
    return {'status': 'observed', 'dll': dll, 'declaredFunctions': functionCount,
      'declaredNames': nameCount, 'symbols': symbols,
      'partial': functionCount > maxSymbols || nameCount > maxSymbols};
  }

  Map<String, Object?> _clr() {
    final directory = _directory(14);
    if (directory == null) {
      return {'status': 'not-declared', 'partial': false};
    }
    final (rva, size) = directory;
    if (size < 72) {
      throw const FormatException('Truncated CLR header');
    }
    final at = _map(rva, 72).$1;
    final cb = _u32(at);
    if (cb < 72 || cb > size) {
      throw const FormatException('Invalid CLR header size');
    }
    final meta = _u32(at + 8);
    final metaSize = _u32(at + 12);
    if (metaSize < 16) {
      throw const FormatException('CLR metadata root missing');
    }
    final offset = _map(meta, metaSize).$1;
    if (_u32(offset) != 0x424a5342) {
      throw const FormatException('CLR metadata BSJB signature missing');
    }
    final versionLength = _u32(offset + 12);
    if (versionLength > 256 || versionLength > metaSize - 16) {
      throw const FormatException('Invalid CLR metadata version length');
    }
    final version = ascii.decode(bytes.sublist(offset + 16, offset + 16 + versionLength),
        allowInvalid: true).split('\u0000').first;
    final flags = _u32(at + 16);
    return {'status': 'managed-metadata-observed', 'partial': true,
      'runtimeMajor': _u16(at + 4), 'runtimeMinor': _u16(at + 6),
      'metadataVersion': version, 'metadataRva': meta, 'metadataBytes': metaSize,
      'ilOnlyFlag': (flags & 1) != 0,
      'entryPointKind': (flags & 0x10) != 0 ? 'native-rva' : 'metadata-token',
      'entryPointValue': _u32(at + 20),
      'note': 'CLR header and metadata signature only, not verified assembly tables.'};
  }
}
