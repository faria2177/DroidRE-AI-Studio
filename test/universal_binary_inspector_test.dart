import 'dart:typed_data';

import 'package:droidre_ai_studio/services/universal_binary_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List fixture(bool is64) {
  final bytes = Uint8List(512);
  final d = ByteData.sublistView(bytes);
  void u16(int at, int v) => d.setUint16(at, v, Endian.little);
  void u32(int at, int v) => d.setUint32(at, v, Endian.little);
  u16(0, 0x5a4d);
  u32(60, 64);
  u32(64, 0x4550);
  u16(68, is64 ? 0x8664 : 0x14c);
  u16(70, 1);
  final size = is64 ? 112 : 96;
  u16(84, size);
  u16(86, 0x2000);
  u16(88, is64 ? 0x20b : 0x10b);
  u32(104, 4096);
  final section = 88 + size;
  bytes.setRange(section, section + 5, '.text'.codeUnits);
  u32(section + 16, 16);
  u32(section + 20, 400);
  u32(section + 36, 0x60000000);
  return bytes;
}

void main() {
  test('reads PE32 and PE32+ section metadata', () {
    for (final is64 in [false, true]) {
      final report = UniversalBinaryInspector.pe(fixture(is64));
      expect(report['kind'], is64 ? 'PE32+' : 'PE32');
      expect(report['dllFlag'], true);
      expect(report['entryPointRva'], 4096);
      expect((report['sections'] as List).single['rawOffset'], 400);
    }
  });

  test('invalid PE raw range is rejected and remains candidate', () {
    final bytes = fixture(false);
    ByteData.sublistView(bytes).setUint32(88 + 96 + 20, 999, Endian.little);
    expect(() => UniversalBinaryInspector.pe(bytes), throwsFormatException);
    expect(UniversalBinaryInspector.inspect(bytes)['kind'], 'MZ candidate');
  });

  test('exact overlapping matches and hex parser', () {
    final bytes = Uint8List.fromList([1, 1, 1, 2]);
    final result = UniversalBinaryInspector.search(bytes,
        UniversalBinaryInspector.pattern('01 01'));
    expect(result.$1, [0, 1]);
    expect(result.$2, false);
    expect(() => UniversalBinaryInspector.pattern('ABC'), throwsFormatException);
    expect(UniversalBinaryInspector.hexPage(bytes, 0), contains('01 01 01 02'));
  });

  test('bounded copy patch leaves initial bytes intact', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final patch = UniversalBinaryInspector.pattern('ff');
    expect(UniversalBinaryInspector.patchedCopy(bytes, 1, patch), [1, 255, 3]);
    expect(bytes, [1, 2, 3]);
    expect(() => UniversalBinaryInspector.patchedCopy(bytes, 3, patch), throwsFormatException);
  });
}
