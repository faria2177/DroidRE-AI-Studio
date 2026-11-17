import 'dart:typed_data';

import 'package:droidre_ai_studio/services/aarch64_preview_decoder.dart';
import 'package:droidre_ai_studio/services/elf_disassembly_inspector.dart';
import 'package:droidre_ai_studio/services/elf_symbol_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

import 'elf_section_inspector_test.dart' show makeElf64Sections;
import 'elf_symbol_inspector_test.dart' show makeElf64;

void main() {
  Aarch64Instruction decode(int word) => Aarch64PreviewDecoder.decode(word, 0x1000);

  test('decodes direct, conditional and register branch instructions', () {
    expect(decode(0x94000002).mnemonic, 'bl');
    expect(decode(0x94000002).target, 0x1008);
    expect(decode(0x17ffffff).target, 0xffc);
    expect(decode(0x54000040).mnemonic, 'b.eq');
    expect(decode(0x54000040).target, 0x1008);
    expect(decode(0xb4000040).operands, 'x0, 0x1008');
    expect(decode(0xb6000040).operands, 'x0, #32, 0x1008');
    expect(decode(0xd65f03c0).operands, 'x30');
    expect(decode(0xd63f0020).mnemonic, 'blr');
  });

  test('decodes arithmetic, constants, address and load/store forms', () {
    expect(decode(0xd10043ff).operands, 'sp, sp, #16');
    expect(decode(0x910043ff).mnemonic, 'add');
    expect(decode(0xd2800020).operands, 'x0, #1');
    expect(decode(0xf94007e0).operands, 'x0, [sp, #8]');
    expect(decode(0xb90007e0).operands, 'w0, [sp, #4]');
    expect(decode(0x90000000).operands, 'x0, 0x1000');
    expect(decode(0xd503201f).mnemonic, 'nop');
    expect(decode(0xffffffff).supported, isFalse);
    expect(decode(0x52c00000).supported, isFalse); // Invalid 32-bit halfword.
  });

  test('paginates real executable section and preserves addresses', () {
    final bytes = makeElf64Sections();
    final data = ByteData.sublistView(bytes);
    data.setUint32(0x80, 0x94000001, Endian.little);
    data.setUint32(0x84, 0xd65f03c0, Endian.little);
    final first = ElfDisassemblyInspector.inspectBytes(bytes, 1, limit: 1);
    expect(first.instructions.single.target, 0x1004);
    expect(first.hasNext, isTrue);
    final last = ElfDisassemblyInspector.inspectBytes(bytes, 1, offset: first.nextOffset);
    expect(last.fileOffset, 0x84);
    expect(last.instructions.single.address, 0x1004);
    expect(last.instructions.single.mnemonic, 'ret');
    expect(last.hasNext, isFalse);
  });

  test('restricts a sized function to its verified section range', () {
    final bytes = makeElf64Sections();
    ByteData.sublistView(bytes).setUint32(0x84, 0xd65f03c0, Endian.little);
    ElfSymbol symbol(int size) => ElfSymbol(name: 'example', type: 'FUNC',
      binding: 'GLOBAL', visibility: 'DEFAULT', sectionIndex: 1,
      dynamic: true, imported: false, exported: true, value: 0x1004, size: size);
    final page = ElfDisassemblyInspector.inspectBytes(bytes, 1, function: symbol(4));
    expect(page.label, 'example');
    expect(page.instructions.single.mnemonic, 'ret');
    expect(page.fileOffset, 0x84);
    expect(() => ElfDisassemblyInspector.inspectBytes(bytes, 1, function: symbol(8)),
      throwsFormatException);
    expect(() => ElfDisassemblyInspector.inspectBytes(bytes, 1, function: symbol(0)),
      throwsFormatException);
  });

  test('rejects unsupported architecture, data sections and misaligned pages', () {
    final bytes = makeElf64Sections();
    expect(() => ElfDisassemblyInspector.inspectBytes(bytes, 2), throwsFormatException);
    expect(() => ElfDisassemblyInspector.inspectBytes(bytes, 3), throwsFormatException);
    expect(() => ElfDisassemblyInspector.inspectBytes(bytes, 1, offset: 2), throwsFormatException);
    expect(() => ElfDisassemblyInspector.inspectBytes(bytes, 1, offset: 8), throwsFormatException);
    expect(() => ElfDisassemblyInspector.inspectBytes(makeElf64Sections(bigEndian: true), 1),
        throwsFormatException);
    ByteData.sublistView(bytes).setUint16(18, 62, Endian.little);
    expect(() => ElfDisassemblyInspector.inspectBytes(bytes, 1), throwsFormatException);
  });

  test('reads native symbol value and size from ELF64 records', () {
    final bytes = makeElf64();
    final data = ByteData.sublistView(bytes);
    data.setUint64(0x100 + 24 + 8, 0x1234, Endian.little);
    data.setUint64(0x100 + 24 + 16, 64, Endian.little);
    final symbol = ElfSymbolInspector.inspectBytes(bytes).symbols.first;
    expect(symbol.value, 0x1234);
    expect(symbol.size, 64);
  });
}
