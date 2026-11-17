import 'dart:typed_data';

import 'package:droidre_ai_studio/services/universal_binary_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List directoryFixture({bool wide = false}) {
  final bytes = Uint8List(2048);
  final data = ByteData.sublistView(bytes);
  void u16(int at, int v) => data.setUint16(at, v, Endian.little);
  void u32(int at, int v) => data.setUint32(at, v, Endian.little);
  void text(int at, String s) => bytes.setRange(at, at + s.length, s.codeUnits);
  u16(0, 0x5a4d);
  u32(60, 64);
  u32(64, 0x4550);
  u16(68, wide ? 0x8664 : 0x14c);
  u16(70, 1);
  final prefix = wide ? 112 : 96;
  final optSize = prefix + 128;
  u16(84, optSize);
  u16(88, wide ? 0x20b : 0x10b);
  u32(88 + prefix - 4, 16);
  final dirs = 88 + prefix;
  u32(dirs, 0x1200);
  u32(dirs + 4, 0x100);
  u32(dirs + 8, 0x1000);
  u32(dirs + 12, 40);
  u32(dirs + 112, 0x1400);
  u32(dirs + 116, 72);
  final section = 88 + optSize;
  text(section, '.rdata');
  u32(section + 8, 1536);
  u32(section + 12, 0x1000);
  u32(section + 16, 1536);
  u32(section + 20, 512);
  int off(int rva) => 512 + rva - 0x1000;
  // Import directory + two lookup thunks and terminator.
  u32(off(0x1000), 0x1100);
  u32(off(0x1000) + 12, 0x1080);
  u32(off(0x1000) + 16, 0x1140);
  text(off(0x1080), 'demo.dll');
  u32(off(0x1100), 0x1180);
  if (wide) {
    u32(off(0x1108), 7);
    u32(off(0x1108) + 4, 0x80000000);
  } else {
    u32(off(0x1104), 0x80000007);
  }
  u16(off(0x1180), 3);
  text(off(0x1180) + 2, 'DemoFunction');
  // Export directory: named forwarder and ordinal-only RVA.
  final e = off(0x1200);
  u32(e + 12, 0x1240);
  u32(e + 16, 1);
  u32(e + 20, 2);
  u32(e + 24, 1);
  u32(e + 28, 0x1260);
  u32(e + 32, 0x1268);
  u32(e + 36, 0x126c);
  text(off(0x1240), 'sample.dll');
  u32(off(0x1260), 0x1280);
  u32(off(0x1264), 0x1500);
  u32(off(0x1268), 0x1290);
  text(off(0x1280), 'demo.Target');
  text(off(0x1290), 'Exported');
  final clr = off(0x1400);
  u32(clr, 72);
  u16(clr + 4, 2);
  u16(clr + 6, 5);
  u32(clr + 8, 0x1480);
  u32(clr + 12, 32);
  u32(clr + 16, 1);
  final metadata = off(0x1480);
  u32(metadata, 0x424a5342);
  u32(metadata + 12, 12);
  text(metadata + 16, 'v4.0.30319');
  return bytes;
}

Map analysis(Uint8List bytes) =>
    UniversalBinaryInspector.inspect(bytes)['directoryAnalysis'] as Map;

void main() {
  test('PE32 and PE32+ decode named and ordinal imports', () {
    for (final wide in [false, true]) {
      final imports = analysis(directoryFixture(wide: wide))['imports'] as Map;
      final library = (imports['libraries'] as List).single as Map;
      expect(library['dll'], 'demo.dll');
      expect(library['symbols'], [
        {'name': 'DemoFunction', 'hint': 3}, {'ordinal': 7},
      ]);
      expect(imports['partial'], false);
    }
  });

  test('exports retain forwarded names and ordinal-only entries', () {
    final exports = analysis(directoryFixture())['exports'] as Map;
    final symbols = exports['symbols'] as List;
    expect(symbols[0]['forwarder'], 'demo.Target');
    expect(symbols[0]['names'], ['Exported']);
    expect(symbols[1]['ordinal'], 2);
    expect(symbols[1]['names'], isEmpty);
  });

  test('CLR metadata magic and version are observed', () {
    final clr = analysis(directoryFixture())['clr'] as Map;
    expect(clr['status'], 'managed-metadata-observed');
    expect(clr['metadataVersion'], 'v4.0.30319');
    expect(clr['ilOnlyFlag'], true);
  });

  test('bad import RVA does not suppress valid exports and CLR', () {
    final bytes = directoryFixture();
    ByteData.sublistView(bytes).setUint32(512 + 12, 0x9999, Endian.little);
    final result = analysis(bytes);
    expect(result['imports']['status'], 'unresolved');
    expect(result['exports']['status'], 'observed');
    expect(result['clr']['status'], 'managed-metadata-observed');
  });
}
