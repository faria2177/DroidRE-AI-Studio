import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'elf_inspector.dart';
import 'package_binary_reader.dart';

@immutable
class ElfSymbol {
  const ElfSymbol({
    required this.name,
    required this.type,
    required this.binding,
    required this.visibility,
    required this.sectionIndex,
    required this.dynamic,
    required this.imported,
    required this.exported,
    this.value = 0,
    this.size = 0,
  });

  final String name;
  final String type;
  final String binding;
  final String visibility;
  final int sectionIndex;
  final bool dynamic;
  final bool imported;
  final bool exported;
  final int value;
  final int size;
}

@immutable
class ElfSymbolReport {
  const ElfSymbolReport({
    required this.symbols,
    required this.scanned,
    required this.imports,
    required this.exports,
    required this.truncated,
    required this.warnings,
  });

  final List<ElfSymbol> symbols;
  final int scanned;
  final int imports;
  final int exports;
  final bool truncated;
  final List<String> warnings;
}

/// Safely reads ELF32/ELF64 symbol table sections without executing native
/// code. Import/export classification applies to DYNAMIC symbols only.
class ElfSymbolInspector {
  const ElfSymbolInspector._();

  static const maxResults = 500;
  static const maxScannedSymbols = 100000;
  static const maxSections = 4096;
  static const maxNameBytes = 2048;

  static Future<ElfSymbolReport> inspectEntry(
    String apkPath,
    String entryName,
  ) => Isolate.run(() => inspectBytes(PackageBinaryReader.read(
    apkPath: apkPath,
    entryName: entryName,
    maxBytes: ElfInspector.maxBytes,
  )));

  static ElfSymbolReport inspectBytes(
    Uint8List bytes, {
    int resultLimit = maxResults,
    int scanLimit = maxScannedSymbols,
    Set<String>? exactNames,
  }) {
    if (bytes.length < 52 || bytes.length > ElfInspector.maxBytes ||
        resultLimit < 1 || resultLimit > maxResults ||
        scanLimit < 1 || scanLimit > maxScannedSymbols ||
        bytes[0] != 0x7f || bytes[1] != 0x45 ||
        bytes[2] != 0x4c || bytes[3] != 0x46) {
      throw const FormatException('Invalid ELF symbol inspection input');
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
      throw const FormatException('Invalid ELF header version or size');
    }
    final data = ByteData.sublistView(bytes);
    void check(int at, int size, [int? end]) {
      final limit = end ?? bytes.length;
      if (at < 0 || size < 0 || limit > bytes.length ||
          at > limit || size > limit - at) {
        throw const FormatException('ELF section offset outside file bounds');
      }
    }
    int u8(int at) {
      check(at, 1);
      return bytes[at];
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

    final sectionOffset = is64 ? u64(40) : u32(32);
    final sectionEntrySize = u16(is64 ? 58 : 46);
    final sectionCount = u16(is64 ? 60 : 48);
    final warnings = <String>[];
    if (sectionCount == 0 || sectionOffset == 0) {
      return const ElfSymbolReport(
        symbols: [], scanned: 0, imports: 0, exports: 0,
        truncated: false,
        warnings: ['No section header table; dynamic-segment fallback not implemented'],
      );
    }
    final minSectionSize = is64 ? 64 : 40;
    if (sectionCount > maxSections || sectionEntrySize < minSectionSize) {
      throw const FormatException('Unsupported ELF section table dimensions');
    }
    check(sectionOffset, sectionCount * sectionEntrySize);

    final sections = <_Section>[];
    for (var i = 0; i < sectionCount; i++) {
      final at = sectionOffset + i * sectionEntrySize;
      final type = u32(at + 4);
      final offset = is64 ? u64(at + 24) : u32(at + 16);
      final size = is64 ? u64(at + 32) : u32(at + 20);
      final link = u32(at + (is64 ? 40 : 24));
      final entrySize = is64 ? u64(at + 56) : u32(at + 36);
      // NOBITS section data is virtual and absent from the ELF file.
      if (type != 8) check(offset, size);
      sections.add(_Section(type, offset, size, link, entrySize));
    }
    final symbolTables = <_Section>[
      ...sections.where((s) => s.type == 11), // DYNAMIC first.
      ...sections.where((s) => s.type == 2),
    ];
    if (symbolTables.isEmpty) {
      warnings.add('No SHT_DYNSYM or SHT_SYMTAB sections found');
    }

    final symbols = <ElfSymbol>[];
    var scanned = 0;
    var imports = 0;
    var exports = 0;
    var truncated = false;
    bool hasNameErrors = false;

    String nameAt(_Section strings, int index) {
      if (index >= strings.size) {
        throw const FormatException('ELF string name index out of range');
      }
      final begin = strings.offset + index;
      var end = begin;
      while (end < strings.offset + strings.size &&
          end - begin <= maxNameBytes && u8(end) != 0) {
        end++;
      }
      if (end >= strings.offset + strings.size ||
          end - begin > maxNameBytes) {
        throw const FormatException('Unterminated ELF symbol name');
      }
      return utf8.decode(bytes.sublist(begin, end), allowMalformed: true);
    }

    for (final table in symbolTables) {
      final minEntrySize = is64 ? 24 : 16;
      if (table.entrySize < minEntrySize ||
          table.entrySize > 512 ||
          table.size % table.entrySize != 0 ||
          table.link >= sections.length ||
          sections[table.link].type != 3) {
        throw const FormatException('Invalid ELF symbol table metadata');
      }
      final strtab = sections[table.link];
      final count = table.size ~/ table.entrySize;
      for (var i = 0; i < count; i++) {
        if (scanned >= scanLimit || symbols.length >= resultLimit) {
          truncated = true;
          break;
        }
        scanned++;
        final at = table.offset + i * table.entrySize;
        final nameIndex = u32(at);
        final info = u8(at + (is64 ? 4 : 12));
        final other = u8(at + (is64 ? 5 : 13));
        final sectionIndex = u16(at + (is64 ? 6 : 14));
        String name;
        try {
          name = nameAt(strtab, nameIndex);
        } on FormatException {
          hasNameErrors = true;
          continue;
        }
        if (name.isEmpty || (exactNames != null && !exactNames.contains(name))) {
          continue;
        }
        final binding = info >> 4;
        final type = info & 0xf;
        final visibility = other & 3;
        final dynamic = table.type == 11;
        final externallyVisible = visibility == 0 || visibility == 3;
        final globalBinding = binding == 1 || binding == 2 || binding == 10;
        final imported = dynamic && globalBinding && sectionIndex == 0;
        final exported = dynamic && globalBinding && sectionIndex != 0 &&
            externallyVisible;
        if (imported) imports++;
        if (exported) exports++;
        symbols.add(ElfSymbol(
          name: name,
          type: switch (type) {
            0 => 'NOTYPE',
            1 => 'OBJECT',
            2 => 'FUNC',
            3 => 'SECTION',
            4 => 'FILE',
            5 => 'COMMON',
            6 => 'TLS',
            10 => 'GNU_IFUNC',
            _ => 'TYPE_$type',
          },
          binding: switch (binding) {
            0 => 'LOCAL',
            1 => 'GLOBAL',
            2 => 'WEAK',
            10 => 'GNU_UNIQUE',
            _ => 'BIND_$binding',
          },
          visibility: switch (visibility) {
            0 => 'DEFAULT',
            1 => 'INTERNAL',
            2 => 'HIDDEN',
            3 => 'PROTECTED',
            _ => 'OTHER',
          },
          sectionIndex: sectionIndex,
          value: is64 ? u64(at + 8) : u32(at + 4),
          size: is64 ? u64(at + 16) : u32(at + 8),
          dynamic: dynamic,
          imported: imported,
          exported: exported,
        ));
      }
      if (truncated) break;
    }
    if (hasNameErrors) {
      warnings.add('Malformed symbol names were skipped');
    }
    if (truncated) {
      warnings.add('Symbol results/scan limited; counts cover inspected entries only');
    }
    return ElfSymbolReport(
      symbols: symbols,
      scanned: scanned,
      imports: imports,
      exports: exports,
      truncated: truncated,
      warnings: warnings,
    );
  }
}

class _Section {
  const _Section(this.type, this.offset, this.size, this.link, this.entrySize);
  final int type;
  final int offset;
  final int size;
  final int link;
  final int entrySize;
}
