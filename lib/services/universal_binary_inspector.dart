import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'elf_inspector.dart';

class UniversalBinaryInspector {
  const UniversalBinaryInspector._();
  static const maxBytes = 32 * 1024 * 1024;
  static const pageSize = 256;
  static const maxMatches = 1000;
  static const maxPattern = 256;

  static Future<Uint8List> load(String path) => Isolate.run(() async {
    final file = File(path);
    if (await file.length() > maxBytes) {
      throw const FormatException('Binary exceeds 32 MiB limit');
    }
    final bytes = await file.openRead(0, maxBytes + 1).fold<List<int>>(
        [], (all, part) => all..addAll(part));
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Empty or oversized binary');
    }
    return Uint8List.fromList(bytes);
  });

  static Map<String, Object?> inspect(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Unsupported binary size');
    }
    final common = <String, Object?>{
      'bytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      'scope': 'Static header evidence only, not execution or signature validation.',
    };
    if (bytes.length >= 2 && bytes[0] == 0x4d && bytes[1] == 0x5a) {
      try {
        return {...common, ...pe(bytes)};
      } on FormatException catch (e) {
        return {...common, 'kind': 'MZ candidate', 'warning': e.message};
      }
    }
    if (bytes.length >= 4 && ascii.decode(bytes.sublist(0, 4),
        allowInvalid: true) == '\u007fELF') {
      try {
        final elf = ElfInspector.inspectBytes(bytes);
        return {...common, 'kind': 'ELF', 'bits': elf.bits,
          'machine': elf.machine, 'byteOrder': elf.byteOrder,
          'entryPoint': elf.entryPoint, 'type': elf.fileType,
          'sectionHeaders': elf.sectionHeaders};
      } on FormatException catch (e) {
        return {...common, 'kind': 'ELF candidate', 'warning': e.message};
      }
    }
    return {...common, 'kind': 'Raw binary / unknown'};
  }

  static Map<String, Object?> pe(Uint8List bytes) {
    final d = ByteData.sublistView(bytes);
    void check(int at, int length) {
      if (at < 0 || length < 0 || at > bytes.length ||
          length > bytes.length - at) {
        throw const FormatException('PE range outside file');
      }
    }
    int u16(int at) => d.getUint16(at, Endian.little);
    int u32(int at) => d.getUint32(at, Endian.little);
    check(0, 64);
    if (u16(0) != 0x5a4d) {
      throw const FormatException('MZ signature missing');
    }
    final peOffset = u32(60);
    check(peOffset, 24);
    if (peOffset < 64 || u32(peOffset) != 0x4550) {
      throw const FormatException('PE signature missing');
    }
    final coff = peOffset + 4;
    final machine = u16(coff);
    final count = u16(coff + 2);
    final optionalSize = u16(coff + 16);
    final flags = u16(coff + 18);
    final opt = coff + 20;
    check(opt, optionalSize);
    if (count < 1 || count > 96 || optionalSize < 2) {
      throw const FormatException('Unsupported PE header dimensions');
    }
    final magic = u16(opt);
    final is64 = magic == 0x20b;
    if (!is64 && magic != 0x10b) {
      throw const FormatException('Unsupported PE optional header magic');
    }
    final prefix = is64 ? 112 : 96;
    if (optionalSize < prefix) {
      throw const FormatException('Truncated PE optional header');
    }
    final sectionTable = opt + optionalSize;
    check(sectionTable, count * 40);
    final directoryCount = u32(opt + prefix - 4);
    if (directoryCount > (optionalSize - prefix) ~/ 8) {
      throw const FormatException('PE directory count exceeds optional header');
    }
    final sections = <Map<String, Object>>[];
    for (var i = 0; i < count; i++) {
      final at = sectionTable + i * 40;
      final name = ascii.decode(bytes.sublist(at, at + 8).takeWhile((v) => v != 0).toList(),
          allowInvalid: true);
      final size = u32(at + 16);
      final offset = u32(at + 20);
      final characteristics = u32(at + 36);
      if (size != 0) {
        check(offset, size);
      }
      sections.add({
        'name': name, 'virtualAddress': u32(at + 12),
        'virtualSize': u32(at + 8), 'rawOffset': offset, 'rawSize': size,
        'executable': (characteristics & 0x20000000) != 0,
        'readable': (characteristics & 0x40000000) != 0,
        'writable': (characteristics & 0x80000000) != 0,
      });
    }
    final directories = <Map<String, Object>>[];
    for (var i = 0; i < directoryCount.clamp(0, 16); i++) {
      final at = opt + prefix + i * 8;
      directories.add({'index': i, 'address': u32(at), 'size': u32(at + 4),
        'addressKind': i == 4 ? 'file-offset' : 'RVA'});
    }
    return {
      'kind': is64 ? 'PE32+' : 'PE32',
      'machine': switch (machine) {
        0x14c => 'x86', 0x8664 => 'x86-64', 0x1c4 => 'ARM Thumb-2',
        0xaa64 => 'ARM64', _ => '0x${machine.toRadixString(16)}',
      },
      'dllFlag': (flags & 0x2000) != 0,
      'entryPointRva': u32(opt + 16),
      'imageBase': '0x${(is64 ? d.getUint64(opt + 24, Endian.little) : u32(opt + 28)).toUnsigned(is64 ? 64 : 32).toRadixString(16)}',
      'subsystem': u16(opt + 68),
      'dllCharacteristics': u16(opt + 70),
      'sections': sections,
      'directories': directories,
      'directoryCount': directoryCount,
      'note': 'Declared directory addresses only; no import/export or certificate parsing.',
    };
  }

  static String hexPage(Uint8List bytes, int offset) {
    if (offset < 0 || offset >= bytes.length) {
      throw const FormatException('Offset outside file');
    }
    final stop = (offset + pageSize).clamp(offset, bytes.length).toInt();
    final out = StringBuffer();
    for (var at = offset; at < stop; at += 16) {
      final row = bytes.sublist(at, (at + 16).clamp(at, stop).toInt());
      final hex = row.map((v) => v.toRadixString(16).padLeft(2, '0')).join(' ');
      final text = String.fromCharCodes(row.map((v) => v >= 32 && v <= 126 ? v : 46));
      out.writeln('${at.toRadixString(16).padLeft(8, '0')}  ${hex.padRight(47)}  |$text|');
    }
    return out.toString();
  }

  static Uint8List pattern(String text, {bool hex = true}) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    if (hex && (compact.isEmpty || compact.length.isOdd ||
        compact.length > maxPattern * 2 ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(compact))) {
      throw const FormatException('Enter 1–256 complete hexadecimal bytes');
    }
    final bytes = hex
        ? List<int>.generate(compact.length ~/ 2, (i) =>
            int.parse(compact.substring(i * 2, i * 2 + 2), radix: 16))
        : utf8.encode(text);
    if (bytes.isEmpty || bytes.length > maxPattern) {
      throw const FormatException('Pattern must contain 1–256 bytes');
    }
    return Uint8List.fromList(bytes);
  }

  /// Linear-time exact search; overlapping matches retained.
  static (List<int>, bool) search(Uint8List bytes, Uint8List needle) {
    if (bytes.length > maxBytes || needle.isEmpty || needle.length > maxPattern) {
      throw const FormatException('Invalid search bounds');
    }
    final failure = List<int>.filled(needle.length, 0);
    for (var i = 1, j = 0; i < needle.length; i++) {
      while (j > 0 && needle[i] != needle[j]) {
        j = failure[j - 1];
      }
      if (needle[i] == needle[j]) {
        j++;
      }
      failure[i] = j;
    }
    final hits = <int>[];
    for (var i = 0, j = 0; i < bytes.length; i++) {
      while (j > 0 && bytes[i] != needle[j]) {
        j = failure[j - 1];
      }
      if (bytes[i] == needle[j]) {
        j++;
      }
      if (j == needle.length) {
        if (hits.length >= maxMatches) {
          return (hits, true);
        }
        hits.add(i - j + 1);
        j = failure[j - 1];
      }
    }
    return (hits, false);
  }

  static Uint8List patchedCopy(Uint8List bytes, int offset, Uint8List replacement) {
    if (bytes.length > maxBytes || offset < 0 || offset > bytes.length ||
        replacement.isEmpty || replacement.length > maxPattern ||
        replacement.length > bytes.length - offset) {
      throw const FormatException('Replacement exceeds file or patch bounds');
    }
    return Uint8List.fromList(bytes)..setRange(offset, offset + replacement.length, replacement);
  }
}
