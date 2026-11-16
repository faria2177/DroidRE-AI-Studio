import 'dart:convert';
import 'dart:typed_data';

import 'package:droidre_ai_studio/services/elf_symbol_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List makeElf64({bool bigEndian = false}) {
  final bytes = Uint8List(768);
  final endian = bigEndian ? Endian.big : Endian.little;
  final d = ByteData.sublistView(bytes);
  void u16(int at, int value) => d.setUint16(at, value, endian);
  void u32(int at, int value) => d.setUint32(at, value, endian);
  void u64(int at, int value) => d.setUint64(at, value, endian);

  bytes.setRange(0, 7, [0x7f, 0x45, 0x4c, 0x46, 2,
    bigEndian ? 2 : 1, 1]);
  u16(16, 3); // shared object
  u16(18, 183); // AArch64
  u16(52, 64);
  u64(40, 0x200); // section header table
  u16(58, 64);
  u16(60, 3);

  final names = <String>['', 'JNI_OnLoad', 'puts', 'secret', 'local_name'];
  final offsets = <int>[];
  var at = 0x80;
  for (final name in names) {
    offsets.add(at - 0x80);
    final chars = utf8.encode(name);
    bytes.setRange(at, at + chars.length, chars);
    at += chars.length;
    bytes[at++] = 0;
  }

  // Five Elf64_Sym entries at 0x100, including the null symbol.
  void sym(int index, int name, int info, int visibility, int shndx) {
    final offset = 0x100 + index * 24;
    u32(offset, offsets[name]);
    bytes[offset + 4] = info;
    bytes[offset + 5] = visibility;
    u16(offset + 6, shndx);
  }
  sym(1, 1, 0x12, 0, 1); // exported global function
  sym(2, 2, 0x12, 0, 0); // imported global function
  sym(3, 3, 0x12, 2, 1); // hidden: never exported
  sym(4, 4, 0x02, 0, 1); // local: never exported

  void section(int i, int type, int offset, int length,
      int link, int entrySize) {
    final start = 0x200 + i * 64;
    u32(start + 4, type);
    u64(start + 24, offset);
    u64(start + 32, length);
    u32(start + 40, link);
    u64(start + 56, entrySize);
  }
  section(1, 3, 0x80, at - 0x80, 0, 0); // .dynstr
  section(2, 11, 0x100, 5 * 24, 1, 24); // .dynsym
  return bytes;
}

Uint8List makeElf32BigEndian() {
  final bytes = Uint8List(512);
  const endian = Endian.big;
  final d = ByteData.sublistView(bytes);
  void u16(int at, int value) => d.setUint16(at, value, endian);
  void u32(int at, int value) => d.setUint32(at, value, endian);

  bytes.setRange(0, 7, [0x7f, 0x45, 0x4c, 0x46, 1, 2, 1]);
  u16(16, 3);
  u16(18, 40);
  u16(40, 52);
  u32(32, 0x140);
  u16(46, 40);
  u16(48, 3);

  final names = utf8.encode('\u0000imported\u0000exported\u0000');
  bytes.setRange(0x80, 0x80 + names.length, names);

  // Elf32_Sym layout: name, value, size, info, other, shndx
  void sym(int index, int name, int info, int section) {
    final at = 0xc0 + 16 * index;
    u32(at, name);
    bytes[at + 12] = info;
    u16(at + 14, section);
  }
  sym(1, 1, 0x12, 0);
  sym(2, 10, 0x12, 1);

  void section(int i, int type, int offset, int length,
      int link, int entrySize) {
    final at = 0x140 + i * 40;
    u32(at + 4, type);
    u32(at + 16, offset);
    u32(at + 20, length);
    u32(at + 24, link);
    u32(at + 36, entrySize);
  }
  section(1, 3, 0x80, names.length, 0, 0);
  section(2, 11, 0xc0, 3 * 16, 1, 16);
  return bytes;
}

void main() {
  test('identifies imported, exported, hidden and local ELF64 symbols', () {
    final report = ElfSymbolInspector.inspectBytes(makeElf64());
    expect(report.scanned, 5);
    expect(report.symbols, hasLength(4));
    expect(report.imports, 1);
    expect(report.exports, 1);
    expect(report.truncated, isFalse);
    expect(report.symbols.singleWhere((x) => x.name == 'JNI_OnLoad').exported,
        isTrue);
    expect(report.symbols.singleWhere((x) => x.name == 'puts').imported,
        isTrue);
    expect(report.symbols.singleWhere((x) => x.name == 'secret').exported,
        isFalse);
    expect(report.symbols.singleWhere((x) => x.name == 'local_name').exported,
        isFalse);
  });

  test('supports big-endian ELF64 and ELF32 symbol records', () {
    final elf64 = ElfSymbolInspector.inspectBytes(makeElf64(bigEndian: true));
    final elf32 = ElfSymbolInspector.inspectBytes(makeElf32BigEndian());
    expect(elf64.imports, 1);
    expect(elf64.exports, 1);
    expect(elf32.imports, 1);
    expect(elf32.exports, 1);
    expect(elf32.symbols.map((x) => x.name).toList(),
        containsAll(['imported', 'exported']));
  });

  test('flags limited symbol enumeration and absent section tables', () {
    final limited = ElfSymbolInspector.inspectBytes(
      makeElf64(), resultLimit: 2);
    expect(limited.truncated, isTrue);
    expect(limited.symbols, hasLength(2));
    expect(limited.warnings.join(' '), contains('limited'));

    final noSections = Uint8List.fromList(makeElf64());
    ByteData.sublistView(noSections).setUint64(40, 0, Endian.little);
    final report = ElfSymbolInspector.inspectBytes(noSections);
    expect(report.symbols, isEmpty);
    expect(report.warnings.join(' '), contains('No section header table'));
  });

  test('rejects out-of-bounds tables and invalid string links', () {
    final badOffset = Uint8List.fromList(makeElf64());
    ByteData.sublistView(badOffset)
        .setUint64(40, 0xffffffffffffffff, Endian.little);
    expect(() => ElfSymbolInspector.inspectBytes(badOffset),
        throwsFormatException);

    final badLink = Uint8List.fromList(makeElf64());
    ByteData.sublistView(badLink)
        .setUint32(0x200 + 2 * 64 + 40, 55, Endian.little);
    expect(() => ElfSymbolInspector.inspectBytes(badLink),
        throwsFormatException);

    final badEntrySize = Uint8List.fromList(makeElf64());
    ByteData.sublistView(badEntrySize)
        .setUint64(0x200 + 2 * 64 + 56, 0, Endian.little);
    expect(() => ElfSymbolInspector.inspectBytes(badEntrySize),
        throwsFormatException);
  });

  test('skips corrupt name indices rather than inventing symbols', () {
    final broken = Uint8List.fromList(makeElf64());
    ByteData.sublistView(broken).setUint32(0x100 + 24, 0xffff, Endian.little);
    final report = ElfSymbolInspector.inspectBytes(broken);
    expect(report.warnings.join(' '), contains('Malformed symbol names'));
    expect(report.symbols.any((x) => x.name == 'JNI_OnLoad'), isFalse);
  });
}
