import 'dart:convert';
import 'dart:typed_data';

import 'package:droidre_ai_studio/services/flutter_aot_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

import 'elf_section_inspector_test.dart' show makeElf64Sections;
import 'elf_symbol_inspector_test.dart' show makeElf64;

Uint8List aotElf(List<(String, int, int, int)> symbols) {
  final bytes = Uint8List(4096);
  bytes.setRange(0, 1024, makeElf64Sections());
  final d = ByteData.sublistView(bytes);
  void u16(int at, int v) => d.setUint16(at, v, Endian.little);
  void u32(int at, int v) => d.setUint32(at, v, Endian.little);
  void u64(int at, int v) => d.setUint64(at, v, Endian.little);
  u16(60, 7);
  final names = <int>[0];
  for (final item in symbols) {
    final index = names.length;
    names.addAll([...ascii.encode(item.$1), 0]);
    final at = 0x700 + (symbols.indexOf(item) + 1) * 24;
    u32(at, index);
    bytes[at + 4] = 0x11;
    u16(at + 6, item.$2);
    u64(at + 8, item.$3);
    u64(at + 16, item.$4);
  }
  bytes.setRange(0x500, 0x500 + names.length, names);
  void section(int index, int type, int offset, int length, int link, int entrySize) {
    final at = 0x200 + index * 64;
    u32(at + 4, type);
    u64(at + 24, offset);
    u64(at + 32, length);
    u32(at + 40, link);
    u64(at + 56, entrySize);
  }
  section(5, 3, 0x500, names.length, 0, 0);
  section(6, 11, 0x700, (symbols.length + 1) * 24, 5, 24);
  bytes.setRange(0x90, 0x94, [0xf5, 0xf5, 0xdc, 0xdc]);
  return bytes;
}

void main() {
  test('maps consolidated names including underscore form', () {
    final report = FlutterAotInspector.inspectBytes(aotElf([
      ('_kDartSnapshotData', 2, 0x2000, 6),
      ('kDartSnapshotText', 1, 0x1000, 8),
    ]));
    expect(report.layout, 'consolidated');
    expect(report.partial, isFalse);
    expect(report.regions.first.fileOffset, 0x90);
    expect(report.regions.first.snapshotMagic, isTrue);
    expect(report.regions.last.fileOffset, 0x80);
    expect(report.toJson()['layout'], 'consolidated');
  });

  test('recognizes legacy four-region layout', () {
    final report = FlutterAotInspector.inspectBytes(aotElf([
      ('kDartVmSnapshotData', 2, 0x2000, 6),
      ('kDartVmSnapshotInstructions', 1, 0x1000, 4),
      ('kDartIsolateSnapshotData', 2, 0x2000, 6),
      ('kDartIsolateSnapshotInstructions', 1, 0x1004, 4),
    ]));
    expect(report.layout, 'legacy');
    expect(report.regions, hasLength(4));
  });

  test('deduplicates equivalent names but never assumes symbol extent', () {
    final report = FlutterAotInspector.inspectBytes(aotElf([
      ('kDartSnapshotData', 2, 0x2000, 0),
      ('_kDartSnapshotData', 2, 0x2000, 0),
      ('kDartSnapshotText', 1, 0x1000, 8),
    ]));
    expect(report.regions, hasLength(2));
    expect(report.regions.first.availableBytes, 0);
    expect(report.partial, isTrue);
  });

  test('rejects out-of-section and incompatible executable ranges', () {
    final report = FlutterAotInspector.inspectBytes(aotElf([
      ('kDartSnapshotData', 2, 0x2000, 7),
      ('kDartSnapshotText', 2, 0x2000, 4),
    ]));
    expect(report.regions, isEmpty);
    expect(report.partial, isTrue);
    expect(report.warnings.join(' '), contains('exceeds its section'));
    expect(report.warnings.join(' '), contains('compatible'));
  });

  test('ordinary native ELF does not imply Dart snapshot recovery', () {
    final report = FlutterAotInspector.inspectBytes(makeElf64());
    expect(report.layout, 'not-detected');
    expect(report.partial, isTrue);
    expect(report.scannedSymbols, 5);
  });
}
