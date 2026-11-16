import 'dart:convert';
import 'dart:typed_data';

import 'package:droidre_ai_studio/services/elf_section_inspector.dart';
import 'package:droidre_ai_studio/services/elf_section_hex_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List makeElf64Sections({bool bigEndian = false}) {
  final bytes = Uint8List(1024);
  final data = ByteData.sublistView(bytes);
  final endian = bigEndian ? Endian.big : Endian.little;
  void u16(int at, int value) => data.setUint16(at, value, endian);
  void u32(int at, int value) => data.setUint32(at, value, endian);
  void u64(int at, int value) => data.setUint64(at, value, endian);

  bytes.setRange(0, 7, [
    0x7f, 0x45, 0x4c, 0x46, 2, bigEndian ? 2 : 1, 1,
  ]);
  u16(16, 3); // shared library
  u16(18, 183); // AArch64
  u16(52, 64); // e_ehsize
  u64(40, 0x200); // e_shoff
  u16(58, 64); // e_shentsize
  u16(60, 5); // e_shnum
  u16(62, 4); // e_shstrndx

  final names = utf8.encode(
      '\u0000.text\u0000.rodata\u0000.bss\u0000.shstrtab\u0000');
  bytes.setRange(0x180, 0x180 + names.length, names);

  void section(int i, int name, int type, int flags, int off,
      int size, int addr, int alignment) {
    final at = 0x200 + i * 64;
    u32(at, name);
    u32(at + 4, type);
    u64(at + 8, flags);
    u64(at + 16, addr);
    u64(at + 24, off);
    u64(at + 32, size);
    u64(at + 48, alignment);
  }

  section(1, 1, 1, 0x6, 0x80, 8, 0x1000, 16); // .text
  section(2, 7, 1, 0x2, 0x90, 6, 0x2000, 4); // .rodata
  section(3, 15, 8, 0x3, 0xfffff, 4096, 0x3000, 8); // .bss
  section(4, 20, 3, 0, 0x180, names.length, 0, 1); // .shstrtab
  return bytes;
}

Uint8List makeElf32SectionsBigEndian() {
  final bytes = Uint8List(512);
  final data = ByteData.sublistView(bytes);
  void u16(int at, int value) => data.setUint16(at, value, Endian.big);
  void u32(int at, int value) => data.setUint32(at, value, Endian.big);

  bytes.setRange(0, 7, [0x7f, 0x45, 0x4c, 0x46, 1, 2, 1]);
  u16(16, 3);
  u16(18, 40); // ARM
  u16(40, 52);
  u32(32, 0x140);
  u16(46, 40);
  u16(48, 3);
  u16(50, 2);
  final names = utf8.encode('\u0000.text\u0000.shstrtab\u0000');
  bytes.setRange(0x80, 0x80 + names.length, names);

  void section(int i, int name, int type, int flags, int offset,
      int size, int address) {
    final at = 0x140 + i * 40;
    u32(at, name);
    u32(at + 4, type);
    u32(at + 8, flags);
    u32(at + 12, address);
    u32(at + 16, offset);
    u32(at + 20, size);
    u32(at + 32, 4);
  }

  section(1, 1, 1, 6, 0xc0, 12, 0x1000);
  section(2, 7, 3, 0, 0x80, names.length, 0);
  return bytes;
}

void main() {
  test('ELF64 sections reveal name, flags, offset, size and NOBITS', () {
    final report = ElfSectionInspector.inspectBytes(makeElf64Sections());
    expect(report.totalSections, 5);
    expect(report.sections, hasLength(5));
    expect(report.truncated, isFalse);
    expect(report.warnings, isEmpty);

    final text = report.sections[1];
    expect(text.name, '.text');
    expect(text.type, 'PROGBITS');
    expect(text.flags, containsAll(['ALLOC', 'EXEC']));
    expect(text.size, 8);
    expect(text.offsetHex, '0x80');
    expect(text.addressHex, '0x1000');
    expect(text.fileBacked, isTrue);

    final bss = report.sections[3];
    expect(bss.name, '.bss');
    expect(bss.type, 'NOBITS');
    expect(bss.size, 4096);
    expect(bss.fileBacked, isFalse);
    expect(bss.fileOffset, 0xfffff);
  });

  test('handles big-endian ELF64 and ELF32 section names', () {
    final big64 = ElfSectionInspector.inspectBytes(
      makeElf64Sections(bigEndian: true));
    expect(big64.sections[2].name, '.rodata');
    expect(big64.sections[3].flags, contains('WRITE'));
    final big32 = ElfSectionInspector.inspectBytes(
      makeElf32SectionsBigEndian());
    expect(big32.sections[1].name, '.text');
    expect(big32.sections[1].size, 12);
    expect(big32.sections[1].flags, contains('EXEC'));
  });

  test('supports extended section count and shstrndx in section zero', () {
    final bytes = makeElf64Sections();
    final view = ByteData.sublistView(bytes);
    view.setUint16(60, 0, Endian.little); // e_shnum extended
    view.setUint16(62, 0xffff, Endian.little); // SHN_XINDEX
    view.setUint64(0x200 + 32, 5, Endian.little); // sh0.sh_size
    view.setUint32(0x200 + 40, 4, Endian.little); // sh0.sh_link
    final report = ElfSectionInspector.inspectBytes(bytes);
    expect(report.totalSections, 5);
    expect(report.sections[1].name, '.text');
  });

  test('reports no section table for stripped ELF', () {
    final bytes = makeElf64Sections();
    final view = ByteData.sublistView(bytes);
    view.setUint64(40, 0, Endian.little);
    view.setUint16(60, 0, Endian.little);
    view.setUint16(62, 0, Endian.little);
    final report = ElfSectionInspector.inspectBytes(bytes);
    expect(report.sections, isEmpty);
    expect(report.warnings.single, contains('no section headers'));
  });

  test('marks partial section result and invalid section names', () {
    final limited = ElfSectionInspector.inspectBytes(
        makeElf64Sections(), resultLimit: 2);
    expect(limited.truncated, isTrue);
    expect(limited.sections, hasLength(2));
    expect(limited.totalSections, 5);

    final invalidName = makeElf64Sections();
    ByteData.sublistView(invalidName)
        .setUint32(0x200 + 64, 0xffff, Endian.little);
    final report = ElfSectionInspector.inspectBytes(invalidName);
    expect(report.sections[1].name, contains('invalid name'));
    expect(report.warnings.single, contains('invalid string offsets'));
  });

  test('rejects invalid header tables or file-backed section offsets', () {
    final offset = makeElf64Sections();
    ByteData.sublistView(offset)
        .setUint64(40, 0xffffffffffffffff, Endian.little);
    expect(() => ElfSectionInspector.inspectBytes(offset),
        throwsFormatException);

    final payload = makeElf64Sections();
    ByteData.sublistView(payload)
        .setUint64(0x200 + 64 + 24, 0xffffffffffffffff, Endian.little);
    expect(() => ElfSectionInspector.inspectBytes(payload),
        throwsFormatException);

    final strTable = makeElf64Sections();
    ByteData.sublistView(strTable)
        .setUint16(62, 88, Endian.little);
    expect(() => ElfSectionInspector.inspectBytes(strTable),
        throwsFormatException);
  });

  test('reads bounded hex and ASCII from a file-backed ELF64 section', () {
    final bytes = makeElf64Sections();
    bytes.setRange(0x80, 0x88, [
      0x41, 0x00, 0x7f, 0x20, 0x5a, 0xff, 0x31, 0x0a,
    ]);
    final preview = ElfSectionHexInspector.inspectBytes(bytes, 1);
    expect(preview.sectionName, '.text');
    expect(preview.sectionSize, 8);
    expect(preview.fileOffset, 0x80);
    expect(preview.sectionOffset, 0);
    expect(preview.bytesShown, 8);
    expect(preview.hexDump, contains('0x00000080'));
    expect(preview.hexDump, contains('41 00 7f 20 5a ff 31 0a'));
    expect(preview.hexDump, contains('|A.. Z.1.|'));
    expect(preview.hasNext, isFalse);
    expect(preview.hasPrevious, isFalse);
  });

  test('paginates a section without reading past its boundary', () {
    final bytes = makeElf64Sections();
    for (var i = 0; i < 8; i++) {
      bytes[0x80 + i] = 0x30 + i;
    }
    final first = ElfSectionHexInspector.inspectBytes(
      bytes, 1, byteLimit: 3);
    expect(first.bytesShown, 3);
    expect(first.hasNext, isTrue);
    expect(first.hasPrevious, isFalse);

    final middle = ElfSectionHexInspector.inspectBytes(
      bytes, 1, sectionOffset: 3, byteLimit: 3);
    expect(middle.fileOffset, 0x83);
    expect(middle.hexDump, contains('33 34 35'));
    expect(middle.hasPrevious, isTrue);
    expect(middle.hasNext, isTrue);

    final last = ElfSectionHexInspector.inspectBytes(
      bytes, 1, sectionOffset: 6, byteLimit: 3);
    expect(last.bytesShown, 2);
    expect(last.hasNext, isFalse);
  });

  test('rejects NOBITS, null, invalid index, and invalid preview pages', () {
    final bytes = makeElf64Sections();
    expect(() => ElfSectionHexInspector.inspectBytes(bytes, 3),
        throwsFormatException); // .bss has no on-disk bytes
    expect(() => ElfSectionHexInspector.inspectBytes(bytes, 0),
        throwsFormatException); // NULL section is not file-backed
    expect(() => ElfSectionHexInspector.inspectBytes(bytes, 15),
        throwsFormatException);
    expect(() => ElfSectionHexInspector.inspectBytes(bytes, -1),
        throwsFormatException);
    expect(() => ElfSectionHexInspector.inspectBytes(bytes, 1,
        sectionOffset: 8), throwsFormatException);
    expect(() => ElfSectionHexInspector.inspectBytes(bytes, 1,
        sectionOffset: -1), throwsFormatException);
    expect(() => ElfSectionHexInspector.inspectBytes(bytes, 1,
        byteLimit: ElfSectionHexInspector.pageBytes + 1),
        throwsFormatException);
  });

  test('reads big-endian ELF32 and refuses corrupted section offsets', () {
    final big32 = ElfSectionHexInspector.inspectBytes(
      makeElf32SectionsBigEndian(), 1);
    expect(big32.sectionName, '.text');
    expect(big32.fileOffset, 0xc0);
    expect(big32.bytesShown, 12);

    final corrupt = makeElf64Sections();
    ByteData.sublistView(corrupt)
        .setUint64(0x200 + 64 + 24, 0xffffffffffffffff, Endian.little);
    expect(() => ElfSectionHexInspector.inspectBytes(corrupt, 1),
        throwsFormatException);
  });
}
