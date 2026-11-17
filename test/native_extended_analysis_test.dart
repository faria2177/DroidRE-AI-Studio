import 'dart:typed_data';

import 'package:droidre_ai_studio/services/native_branch_references.dart';
import 'package:droidre_ai_studio/services/native_llvm_disassembler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'elf_section_inspector_test.dart' show makeElf64Sections;

void main() {
  test('finds direct ARM64 call with correct relative target', () {
    final bytes = makeElf64Sections();
    final data = ByteData.sublistView(bytes);
    data.setUint32(0x80, 0x94000001, Endian.little);
    data.setUint32(0x84, 0xd65f03c0, Endian.little);
    final report = NativeBranchReferences.inspectBytes(bytes, 1, 0x1004);
    expect(report.references.single.source, 0x1000);
    expect(report.references.single.call, true);
    expect(report.scannedWords, 2);
    expect(report.partial, false);
    expect(NativeBranchReferences.inspectBytes(bytes, 1, 0x1004, limit: 1).partial, true);
  });

  test('rejects non-executable sections and invalid target alignment', () {
    final bytes = makeElf64Sections();
    expect(() => NativeBranchReferences.inspectBytes(bytes, 2, 0x1000), throwsFormatException);
    expect(() => NativeBranchReferences.inspectBytes(bytes, 1, 0x1001), throwsFormatException);
  });

  test('LLVM arguments are separate, bounded and reject unsafe section names', () {
    expect(NativeLlvmDisassembler.arguments('C:/test path/file.elf', '.text', 4096, 8192),
      ['--disassemble', '--section=.text', '--start-address=0x1000',
       '--stop-address=0x2000', 'C:/test path/file.elf']);
    expect(() => NativeLlvmDisassembler.arguments('file', '.text,.data', 0, 4), throwsFormatException);
    expect(() => NativeLlvmDisassembler.arguments('file', '.text', 0, 4097), throwsFormatException);
  });
}
