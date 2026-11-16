import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'elf_inspector.dart';
import 'package_binary_reader.dart';

@immutable
class ElfSectionInfo {
  const ElfSectionInfo({
    required this.index,
    required this.name,
    required this.type,
    required this.flags,
    required this.fileOffset,
    required this.size,
    required this.virtualAddress,
    required this.alignment,
    required this.fileBacked,
  });

  final int index;
  final String name;
  final String type;
  final List<String> flags;
  final int fileOffset;
  final int size;
  final int virtualAddress;
  final int alignment;
  final bool fileBacked;

  String get offsetHex => '0x${fileOffset.toRadixString(16)}';
  String get addressHex => '0x${virtualAddress.toRadixString(16)}';
}

@immutable
class ElfSectionReport {
  const ElfSectionReport({
    required this.sections,
    required this.totalSections,
    required this.truncated,
    required this.warnings,
  });

  final List<ElfSectionInfo> sections;
  final int totalSections;
  final bool truncated;
  final List<String> warnings;
}

/// Static ELF section metadata inspection. Does not load ELF sections or
/// execute/disassemble machine code. NOBITS sections occupy memory but not
/// file data and must not be checked as file-backed bytes.
class ElfSectionInspector {
  const ElfSectionInspector._();

  static const maxSections = 4096;
  static const maxResults = 1024;
  static const maxNameBytes = 2048;

  static Future<ElfSectionReport> inspectEntry(
    String apkPath,
    String entryName,
  ) => Isolate.run(() => inspectBytes(PackageBinaryReader.read(
    apkPath: apkPath,
    entryName: entryName,
    maxBytes: ElfInspector.maxBytes,
  )));

  static ElfSectionReport inspectBytes(
    Uint8List bytes, {
    int resultLimit = maxResults,
  }) {
    if (resultLimit < 1 || resultLimit > maxResults ||
        bytes.length < 52 || bytes.length > ElfInspector.maxBytes ||
        bytes[0] != 0x7f || bytes[1] != 0x45 ||
        bytes[2] != 0x4c || bytes[3] != 0x46) {
      throw const FormatException('Invalid ELF section inspection input');
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
      throw const FormatException('Invalid ELF header version or length');
    }
    final data = ByteData.sublistView(bytes);
    void check(int at, int length) {
      if (at < 0 || length < 0 ||
          at > bytes.length || length > bytes.length - at) {
        throw const FormatException('ELF section extends outside file');
      }
    }
    int u16(int at) {
      check(at, 2);
      return data.getUint16(at, endian);
    }
    int u32(int at) {
      check(at, 4);
      return data.getUint32(at, endian);
    }
    int u64(int at) {
      check(at, 8);
      return data.getUint64(at, endian);
    }

    final shoff = is64 ? u64(40) : u32(32);
    final shentsize = u16(is64 ? 58 : 46);
    var shnum = u16(is64 ? 60 : 48);
    var shstrndx = u16(is64 ? 62 : 50);
    final warnings = <String>[];

    if (shoff == 0) {
      if (shnum != 0 || shstrndx != 0) {
        throw const FormatException('ELF section table header inconsistent');
      }
      return const ElfSectionReport(
        sections: [], totalSections: 0, truncated: false,
        warnings: ['ELF has no section headers (possibly stripped)'],
      );
    }
    final minEntry = is64 ? 64 : 40;
    if (shentsize < minEntry || shentsize > 512) {
      throw const FormatException('Invalid ELF section header entry size');
    }
    check(shoff, shentsize);
    // Extended ELF indexing stores section count and shstrndx in section 0.
    if (shnum == 0) {
      shnum = is64 ? u64(shoff + 32) : u32(shoff + 20);
    }
    if (shstrndx == 0xffff) {
      shstrndx = u32(shoff + (is64 ? 40 : 24));
    }
    if (shnum < 1 || shnum > maxSections) {
      throw const FormatException('Unsupported ELF section count');
    }
    check(shoff, shnum * shentsize);
    if (shstrndx >= shnum) {
      throw const FormatException('ELF section-name string table index invalid');
    }

    int sectionAt(int i) => shoff + i * shentsize;
    int sectionType(int i) => u32(sectionAt(i) + 4);
    int sectionOffset(int i) {
      final at = sectionAt(i);
      return is64 ? u64(at + 24) : u32(at + 16);
    }
    int sectionSize(int i) {
      final at = sectionAt(i);
      return is64 ? u64(at + 32) : u32(at + 20);
    }

    int? strOffset;
    int? strSize;
    if (shstrndx == 0) {
      warnings.add('Section-name string table absent; using section indexes');
    } else {
      if (sectionType(shstrndx) != 3) {
        throw const FormatException('ELF section-name table is not STRTAB');
      }
      strOffset = sectionOffset(shstrndx);
      strSize = sectionSize(shstrndx);
      check(strOffset, strSize);
    }
    var badNames = false;
    String readName(int index, int nameOffset) {
      if (strOffset == null || strSize == null) {
        return '<section $index>';
      }
      if (nameOffset >= strSize) {
        badNames = true;
        return '<invalid name $index>';
      }
      final start = strOffset + nameOffset;
      var end = start;
      final limit = strOffset + strSize;
      while (end < limit && end - start <= maxNameBytes &&
          bytes[end] != 0) {
        end++;
      }
      if (end >= limit || end - start > maxNameBytes) {
        badNames = true;
        return '<invalid name $index>';
      }
      return utf8.decode(bytes.sublist(start, end), allowMalformed: true);
    }

    final limit = shnum < resultLimit ? shnum : resultLimit;
    final sections = <ElfSectionInfo>[];
    for (var i = 0; i < limit; i++) {
      final at = sectionAt(i);
      final kind = u32(at + 4);
      final flags = is64 ? u64(at + 8) : u32(at + 8);
      final vaddr = is64 ? u64(at + 16) : u32(at + 12);
      final off = sectionOffset(i);
      final size = sectionSize(i);
      final alignment = is64 ? u64(at + 48) : u32(at + 32);
      // Section 0 is the reserved/null entry; NOBITS has no file bytes.
      final backed = kind != 0 && kind != 8;
      if (backed) check(off, size);
      final displayName = readName(i, u32(at));
      sections.add(ElfSectionInfo(
        index: i,
        name: displayName.isEmpty ? '<unnamed $i>' : displayName,
        type: switch (kind) {
          0 => 'NULL',
          1 => 'PROGBITS',
          2 => 'SYMTAB',
          3 => 'STRTAB',
          4 => 'RELA',
          5 => 'HASH',
          6 => 'DYNAMIC',
          7 => 'NOTE',
          8 => 'NOBITS',
          9 => 'REL',
          11 => 'DYNSYM',
          14 => 'INIT_ARRAY',
          15 => 'FINI_ARRAY',
          16 => 'PREINIT_ARRAY',
          17 => 'GROUP',
          18 => 'SYMTAB_SHNDX',
          19 => 'RELR',
          _ => 'TYPE_0x${kind.toRadixString(16)}',
        },
        flags: [
          if ((flags & 1) != 0) 'WRITE',
          if ((flags & 2) != 0) 'ALLOC',
          if ((flags & 4) != 0) 'EXEC',
          if ((flags & 0x10) != 0) 'MERGE',
          if ((flags & 0x20) != 0) 'STRINGS',
          if ((flags & 0x40) != 0) 'INFO_LINK',
          if ((flags & 0x80) != 0) 'LINK_ORDER',
          if ((flags & 0x200) != 0) 'GROUP',
          if ((flags & 0x400) != 0) 'TLS',
          if ((flags & 0x800) != 0) 'COMPRESSED',
        ],
        fileOffset: off,
        size: size,
        virtualAddress: vaddr,
        alignment: alignment,
        fileBacked: backed,
      ));
    }
    if (badNames) {
      warnings.add('Some section names have invalid string offsets');
    }
    if (shnum > resultLimit) {
      warnings.add('Displayed first $resultLimit of $shnum section headers');
    }
    return ElfSectionReport(
      sections: sections,
      totalSections: shnum,
      truncated: shnum > resultLimit,
      warnings: warnings,
    );
  }
}
