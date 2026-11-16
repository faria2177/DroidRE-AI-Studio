import 'dart:convert';
import 'dart:typed_data';

import 'package:droidre_ai_studio/services/elf_dependency_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List makeDynamicElf64({bool bigEndian = false}) {
  final bytes = Uint8List(1024);
  final d = ByteData.sublistView(bytes);
  final endian = bigEndian ? Endian.big : Endian.little;
  void u16(int at, int value) => d.setUint16(at, value, endian);
  void u32(int at, int value) => d.setUint32(at, value, endian);
  void u64(int at, int value) => d.setUint64(at, value, endian);
  bytes.setRange(0, 7, [0x7f, 0x45, 0x4c, 0x46, 2,
    bigEndian ? 2 : 1, 1]);
  u16(16, 3); // ET_DYN
  u16(18, 183); // AArch64
  u16(52, 64);
  u64(40, 0x240); // section table
  u16(58, 64);
  u16(60, 3); // null, strtab, dynamic

  final names = utf8.encode(
      '\u0000libc.so\u0000libm.so\u0000libdemo.so\u0000/system/lib\u0000');
  bytes.setRange(0x80, 0x80 + names.length, names);

  void entry(int i, int tag, int value) {
    final at = 0x100 + i * 16;
    u64(at, tag);
    u64(at + 8, value);
  }
  entry(0, 1, 1); // DT_NEEDED libc.so
  entry(1, 1, 9); // DT_NEEDED libm.so
  entry(2, 14, 17); // DT_SONAME libdemo.so
  entry(3, 15, 28); // DT_RPATH /system/lib
  entry(4, 29, 28); // DT_RUNPATH /system/lib
  entry(5, 0, 0); // DT_NULL

  final strsec = 0x240 + 64;
  u32(strsec + 4, 3); // SHT_STRTAB
  u64(strsec + 24, 0x80);
  u64(strsec + 32, names.length);

  final dynsec = 0x240 + 128;
  u32(dynsec + 4, 6); // SHT_DYNAMIC
  u64(dynsec + 24, 0x100);
  u64(dynsec + 32, 6 * 16);
  u32(dynsec + 40, 1); // linked string section
  u64(dynsec + 56, 16);
  return bytes;
}

Uint8List makeStrippedElf32() {
  final bytes = Uint8List(768);
  final d = ByteData.sublistView(bytes);
  void u16(int at, int value) => d.setUint16(at, value, Endian.little);
  void u32(int at, int value) => d.setUint32(at, value, Endian.little);
  bytes.setRange(0, 7, [0x7f, 0x45, 0x4c, 0x46, 1, 1, 1]);
  u16(16, 3);
  u16(18, 40); // ARM
  u16(40, 52);
  u32(28, 0x40); // Program header table
  u16(42, 32);
  u16(44, 2); // PT_LOAD and PT_DYNAMIC

  void segment(int i, int type, int offset, int vaddr, int size) {
    final at = 0x40 + i * 32;
    u32(at, type);
    u32(at + 4, offset);
    u32(at + 8, vaddr);
    u32(at + 16, size);
  }
  segment(0, 1, 0x100, 0x7000, 0x200);
  segment(1, 2, 0x100, 0x7000, 5 * 8);

  final names = utf8.encode('\u0000libc.so\u0000libdemo.so\u0000');
  bytes.setRange(0x180, 0x180 + names.length, names);
  void entry(int i, int tag, int value) {
    final at = 0x100 + i * 8;
    u32(at, tag);
    u32(at + 4, value);
  }
  entry(0, 5, 0x7080); // DT_STRTAB mapped through PT_LOAD
  entry(1, 10, names.length); // DT_STRSZ
  entry(2, 1, 1); // DT_NEEDED
  entry(3, 14, 9); // DT_SONAME
  entry(4, 0, 0);
  return bytes;
}

void main() {
  test('ELF64 linked dynamic table resolves needed libraries and paths', () {
    final report = ElfDependencyInspector.inspectBytes(makeDynamicElf64());
    expect(report.source, 'SHT_DYNAMIC');
    expect(report.needed, ['libc.so', 'libm.so']);
    expect(report.soname, 'libdemo.so');
    expect(report.rpath, '/system/lib');
    expect(report.runpath, '/system/lib');
    expect(report.examinedEntries, 6);
    expect(report.truncated, isFalse);
    expect(report.warnings, isEmpty);
  });

  test('ELF64 big-endian dynamic records are decoded correctly', () {
    final report = ElfDependencyInspector.inspectBytes(
        makeDynamicElf64(bigEndian: true));
    expect(report.source, 'SHT_DYNAMIC');
    expect(report.needed, ['libc.so', 'libm.so']);
    expect(report.soname, 'libdemo.so');
  });

  test('stripped ELF32 uses PT_DYNAMIC and DT_STRTAB mapping', () {
    final report = ElfDependencyInspector.inspectBytes(makeStrippedElf32());
    expect(report.source, 'PT_DYNAMIC');
    expect(report.needed, ['libc.so']);
    expect(report.soname, 'libdemo.so');
    expect(report.warnings, isEmpty);
  });

  test('reports missing dynamic table without fabricated dependencies', () {
    final elf = Uint8List.fromList(makeDynamicElf64());
    final data = ByteData.sublistView(elf);
    data.setUint16(60, 0, Endian.little); // No sections
    final report = ElfDependencyInspector.inspectBytes(elf);
    expect(report.source, 'none');
    expect(report.needed, isEmpty);
    expect(report.warnings.single, contains('No dynamic table found'));
  });

  test('bounded entry scan explicitly warns about partial inspection', () {
    final report = ElfDependencyInspector.inspectBytes(
      makeDynamicElf64(), entryLimit: 2);
    expect(report.truncated, isTrue);
    expect(report.examinedEntries, 2);
    expect(report.needed, ['libc.so', 'libm.so']);
    expect(report.warnings.join(' '), contains('limited'));
  });

  test('rejects malformed dynamic section links and string indices', () {
    final badLink = Uint8List.fromList(makeDynamicElf64());
    ByteData.sublistView(badLink)
        .setUint32(0x240 + 128 + 40, 9, Endian.little);
    expect(() => ElfDependencyInspector.inspectBytes(badLink),
        throwsFormatException);

    final badName = Uint8List.fromList(makeDynamicElf64());
    ByteData.sublistView(badName)
        .setUint64(0x100 + 8, 9999, Endian.little);
    expect(() => ElfDependencyInspector.inspectBytes(badName),
        throwsFormatException);
  });

  test('rejects out-of-bounds sections and program tables', () {
    final badSection = Uint8List.fromList(makeDynamicElf64());
    ByteData.sublistView(badSection)
        .setUint64(40, 0xffffffffffffffff, Endian.little);
    expect(() => ElfDependencyInspector.inspectBytes(badSection),
        throwsFormatException);

    final badProgram = Uint8List.fromList(makeStrippedElf32());
    ByteData.sublistView(badProgram)
        .setUint32(28, 0xfffffff0, Endian.little);
    expect(() => ElfDependencyInspector.inspectBytes(badProgram),
        throwsFormatException);
  });
}
