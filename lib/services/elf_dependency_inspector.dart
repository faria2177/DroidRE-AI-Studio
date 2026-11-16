import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'elf_inspector.dart';
import 'package_binary_reader.dart';

@immutable
class ElfDependencyReport {
  const ElfDependencyReport({
    required this.needed,
    required this.soname,
    required this.rpath,
    required this.runpath,
    required this.source,
    required this.examinedEntries,
    required this.truncated,
    required this.warnings,
  });

  final List<String> needed;
  final String? soname;
  final String? rpath;
  final String? runpath;
  final String source;
  final int examinedEntries;
  final bool truncated;
  final List<String> warnings;
}

class _ElfSegment {
  const _ElfSegment(this.type, this.offset, this.vaddr, this.fileSize);
  final int type;
  final int offset;
  final int vaddr;
  final int fileSize;
}

class _ElfDynamic {
  const _ElfDynamic(this.offset, this.length, this.entrySize,
      this.stringsOffset, this.stringsLength, this.source);
  final int offset;
  final int length;
  final int entrySize;
  final int? stringsOffset;
  final int? stringsLength;
  final String source;
}

class _ElfTag {
  const _ElfTag(this.tag, this.value);
  final int tag;
  final int value;
}

/// Static ELF32/ELF64 dependency inspection with bounded reads. Prefers
/// SHT_DYNAMIC linked to SHT_STRTAB; falls back to PT_DYNAMIC for stripped
/// shared objects that omit section headers. No library is loaded or run.
class ElfDependencyInspector {
  const ElfDependencyInspector._();

  static const maxDynamicEntries = 16384;
  static const maxDependencies = 256;
  static const maxStringBytes = 2048;
  static const maxSections = 4096;
  static const maxSegments = 1024;

  static Future<ElfDependencyReport> inspectEntry(
    String apkPath,
    String entryName,
  ) => Isolate.run(() => inspectBytes(PackageBinaryReader.read(
    apkPath: apkPath,
    entryName: entryName,
    maxBytes: ElfInspector.maxBytes,
  )));

  static ElfDependencyReport inspectBytes(
    Uint8List bytes, {
    int entryLimit = maxDynamicEntries,
  }) {
    if (entryLimit < 1 || entryLimit > maxDynamicEntries ||
        bytes.length < 52 || bytes.length > ElfInspector.maxBytes ||
        bytes[0] != 0x7f || bytes[1] != 0x45 ||
        bytes[2] != 0x4c || bytes[3] != 0x46) {
      throw const FormatException('Invalid ELF dependency input');
    }
    final is64 = switch (bytes[4]) {
      1 => false,
      2 => true,
      _ => throw const FormatException('Unsupported ELF class'),
    };
    final endian = switch (bytes[5]) {
      1 => Endian.little,
      2 => Endian.big,
      _ => throw const FormatException('Unsupported ELF byte order'),
    };
    if (bytes[6] != 1 || bytes.length < (is64 ? 64 : 52)) {
      throw const FormatException('Incomplete ELF header');
    }
    final data = ByteData.sublistView(bytes);

    void check(int offset, int size) {
      if (offset < 0 || size < 0 ||
          offset > bytes.length || size > bytes.length - offset) {
        throw const FormatException('ELF dynamic data exceeds file bounds');
      }
    }
    int u16(int at) { check(at, 2); return data.getUint16(at, endian); }
    int u32(int at) { check(at, 4); return data.getUint32(at, endian); }
    int word(int at) {
      check(at, is64 ? 8 : 4);
      return is64 ? data.getUint64(at, endian) : u32(at);
    }

    final phoff = is64 ? word(32) : u32(28);
    final phentsize = u16(is64 ? 54 : 42);
    final phnum = u16(is64 ? 56 : 44);
    final shoff = is64 ? word(40) : u32(32);
    final shentsize = u16(is64 ? 58 : 46);
    final shnum = u16(is64 ? 60 : 48);
    final segments = <_ElfSegment>[];
    if (phnum != 0) {
      if (phnum > maxSegments || phentsize < (is64 ? 56 : 32)) {
        throw const FormatException('Unsupported ELF program header layout');
      }
      check(phoff, phnum * phentsize);
      for (var i = 0; i < phnum; i++) {
        final at = phoff + i * phentsize;
        final type = u32(at);
        final offset = is64 ? word(at + 8) : u32(at + 4);
        final vaddr = is64 ? word(at + 16) : u32(at + 8);
        final length = is64 ? word(at + 32) : u32(at + 16);
        if (type == 1 || type == 2) {
          check(offset, length);
          segments.add(_ElfSegment(type, offset, vaddr, length));
        }
      }
    }

    _ElfDynamic? info;
    if (shnum != 0) {
      if (shnum > maxSections || shentsize < (is64 ? 64 : 40)) {
        throw const FormatException('Unsupported ELF section header layout');
      }
      check(shoff, shnum * shentsize);
      for (var i = 0; i < shnum; i++) {
        final at = shoff + i * shentsize;
        if (u32(at + 4) != 6) {
          continue;
        } // SHT_DYNAMIC
        final offset = is64 ? word(at + 24) : u32(at + 16);
        final size = is64 ? word(at + 32) : u32(at + 20);
        final link = u32(at + (is64 ? 40 : 24));
        final entsize = is64 ? word(at + 56) : u32(at + 36);
        if (link >= shnum || entsize < (is64 ? 16 : 8) ||
            entsize > 256 || size % entsize != 0) {
          throw const FormatException('Invalid SHT_DYNAMIC entry layout');
        }
        check(offset, size);
        final linked = shoff + link * shentsize;
        if (u32(linked + 4) != 3) {
          throw const FormatException('SHT_DYNAMIC string link is invalid');
        }
        final strOffset = is64 ? word(linked + 24) : u32(linked + 16);
        final strSize = is64 ? word(linked + 32) : u32(linked + 20);
        check(strOffset, strSize);
        info = _ElfDynamic(
          offset, size, entsize, strOffset, strSize, 'SHT_DYNAMIC');
        break;
      }
    }

    if (info == null) {
      for (final segment in segments) {
        if (segment.type != 2) {
          continue;
        }
        final minSize = is64 ? 16 : 8;
        if (segment.fileSize % minSize != 0) {
          throw const FormatException('Invalid PT_DYNAMIC size');
        }
        info = _ElfDynamic(segment.offset, segment.fileSize, minSize,
            null, null, 'PT_DYNAMIC');
        break;
      }
    }

    if (info == null) {
      return const ElfDependencyReport(
        needed: [], soname: null, rpath: null, runpath: null,
        source: 'none', examinedEntries: 0, truncated: false,
        warnings: ['No dynamic table found; dependencies cannot be inspected'],
      );
    }

    final table = info;
    final tags = <_ElfTag>[];
    final count = table.length ~/ table.entrySize;
    var terminated = false;
    var scanned = 0;
    for (var i = 0; i < count && scanned < entryLimit; i++) {
      final at = table.offset + i * table.entrySize;
      final tag = word(at);
      final value = word(at + (is64 ? 8 : 4));
      scanned++;
      if (tag == 0) {
        terminated = true;
        break;
      }
      if (tag == 1 || tag == 14 || tag == 15 || tag == 29 ||
          tag == 5 || tag == 10) {
        tags.add(_ElfTag(tag, value));
      }
    }
    final truncated = !terminated && scanned >= entryLimit &&
        count > scanned;
    final warnings = <String>[];
    if (!terminated) {
      warnings.add(truncated ? 'Dynamic entries limited for inspection' :
          'Dynamic table has no DT_NULL terminator');
    }

    int? stringsOffset = table.stringsOffset;
    int? stringsLength = table.stringsLength;
    if (stringsOffset == null || stringsLength == null) {
      int? straddr;
      int? strsz;
      for (final t in tags) {
        if (t.tag == 5) straddr = t.value;
        if (t.tag == 10) strsz = t.value;
      }
      if (straddr == null || strsz == null) {
        warnings.add('DT_STRTAB/DT_STRSZ unavailable: names cannot be decoded');
      } else {
        for (final segment in segments) {
          if (segment.type != 1 || straddr < segment.vaddr) {
            continue;
          }
          final relative = straddr - segment.vaddr;
          if (relative > segment.fileSize ||
              strsz > segment.fileSize - relative) {
            continue;
          }
          stringsOffset = segment.offset + relative;
          stringsLength = strsz;
          break;
        }
        if (stringsOffset == null) {
          warnings.add('DT_STRTAB virtual address is not file-backed by PT_LOAD');
        }
      }
    }

    String decodeName(int index) {
      if (stringsOffset == null || stringsLength == null ||
          index >= stringsLength) {
        throw const FormatException('ELF dynamic string index invalid');
      }
      final begin = stringsOffset + index;
      final endLimit = stringsOffset + stringsLength;
      var end = begin;
      while (end < endLimit && end - begin <= maxStringBytes &&
          bytes[end] != 0) {
        end++;
      }
      if (end >= endLimit || end - begin > maxStringBytes) {
        throw const FormatException('Invalid dynamic string termination');
      }
      return utf8.decode(bytes.sublist(begin, end), allowMalformed: true);
    }

    final needed = <String>[];
    String? soname;
    String? rpath;
    String? runpath;
    if (stringsOffset != null && stringsLength != null) {
      for (final tag in tags) {
        if (tag.tag != 1 && tag.tag != 14 &&
            tag.tag != 15 && tag.tag != 29) {
          continue;
        }
        final name = decodeName(tag.value);
        if (tag.tag == 1) {
          if (needed.length >= maxDependencies) {
            warnings.add('Dependency list limited to $maxDependencies names');
            break;
          }
          needed.add(name);
        } else if (tag.tag == 14) {
          soname = name;
        } else if (tag.tag == 15) {
          rpath = name;
        } else if (tag.tag == 29) {
          runpath = name;
        }
      }
    }

    return ElfDependencyReport(
      needed: needed, soname: soname, rpath: rpath,
      runpath: runpath, source: table.source,
      examinedEntries: scanned, truncated: truncated,
      warnings: warnings,
    );
  }
}
