import 'dart:typed_data';

import 'package:droidre_ai_studio/services/elf_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List elfHeader({required bool is64, required bool bigEndian}) {
  final bytes = Uint8List(is64 ? 64 : 52);
  bytes.setRange(0, 7, [0x7f, 0x45, 0x4c, 0x46, is64 ? 2 : 1,
    bigEndian ? 2 : 1, 1]);
  final data = ByteData.sublistView(bytes);
  final endian = bigEndian ? Endian.big : Endian.little;
  data.setUint16(16, 3, endian);
  data.setUint16(18, is64 ? 183 : 40, endian);
  if (is64) {
    data.setUint64(24, 0x12340000, endian);
    data.setUint16(52, 64, endian);
    data.setUint16(56, 4, endian);
    data.setUint16(60, 9, endian);
  } else {
    data.setUint32(24, 0x12340000, endian);
    data.setUint16(40, 52, endian);
    data.setUint16(44, 4, endian);
    data.setUint16(48, 9, endian);
  }
  return bytes;
}

void main() {
  test('reads little-endian ARM ELF32', () {
    final result = ElfInspector.inspectBytes(elfHeader(is64: false, bigEndian: false));
    expect(result.bits, 32);
    expect(result.machine, contains('ARM'));
    expect(result.programHeaders, 4);
    expect(result.sectionHeaders, 9);
  });

  test('reads big-endian AArch64 ELF64', () {
    final result = ElfInspector.inspectBytes(elfHeader(is64: true, bigEndian: true));
    expect(result.bits, 64);
    expect(result.machine, contains('AArch64'));
    expect(result.byteOrder, 'Big-endian');
    expect(result.entryPoint, '0x12340000');
  });

  test('rejects malformed ELF header', () {
    final bytes = elfHeader(is64: true, bigEndian: false);
    bytes[4] = 7;
    expect(() => ElfInspector.inspectBytes(bytes), throwsFormatException);
    expect(() => ElfInspector.inspectBytes(Uint8List(10)), throwsFormatException);
  });
}
