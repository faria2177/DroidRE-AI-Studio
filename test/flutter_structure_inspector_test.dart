import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:droidre_ai_studio/services/flutter_structure_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

import 'elf_section_inspector_test.dart' show makeElf64Sections;
import 'flutter_aot_inspector_test.dart' show aotElf;

void main() {
  test('scans only declared sized snapshot data and preserves offsets', () {
    final bytes = aotElf([
      ('kDartSnapshotData', 2, 0x2000, 32),
      ('kDartSnapshotText', 1, 0x1000, 8),
    ]);
    ByteData.sublistView(bytes).setUint64(0x280 + 32, 32, Endian.little);
    final text = ascii.encode('package:demo/main.dart');
    bytes.setRange(0x94, 0x94 + text.length, text);
    final result = FlutterStructureInspector.scanBinary(bytes);
    final hits = result['strings'] as List;
    expect(result['fallbackSectionScan'], false);
    expect(hits.single['text'], 'package:demo/main.dart');
    expect(hits.single['fileOffset'], '0x94');
    expect(hits.single['kind'], 'dart-uri-like');
    expect(result['scannedBytes'], 32);
  });

  test('fallback skips executable data and marks scan scope', () {
    final bytes = makeElf64Sections();
    bytes.setRange(0x80, 0x88, ascii.encode('TEXTCODE'));
    bytes.setRange(0x90, 0x96, ascii.encode('HELLO!'));
    final result = FlutterStructureInspector.scanBinary(bytes);
    expect(result['fallbackSectionScan'], true);
    expect(result['partial'], true);
    final hits = result['strings'] as List;
    expect(hits.single['text'], 'HELLO!');
    expect(FlutterStructureInspector.scanBinary(bytes, byteLimit: 5)['strings'], isEmpty);
  });

  test('indexes Flutter asset paths without decoding payloads', () {
    final archive = Archive()
      ..addFile(ArchiveFile.string('assets/flutter_assets/AssetManifest.bin', 'binary'))
      ..addFile(ArchiveFile.string('assets/flutter_assets/packages/foo/icons/a.png', 'image'))
      ..addFile(ArchiveFile.string('assets/flutter_assets/assets/data.json', '{}'))
      ..addFile(ArchiveFile.string('assets/other.txt', 'not Flutter'));
    final result = FlutterStructureInspector.inventory(archive);
    expect(result['assetCount'], 3);
    expect(result['packageFolders'], ['foo']);
    final list = result['entries'] as List;
    expect(list.first['kind'], 'manifest-file');
    expect(result['partial'], false);
  });

  test('unsafe asset paths are omitted and marked partial', () {
    final archive = Archive()
      ..addFile(ArchiveFile.string('assets/flutter_assets/../secret', 'x'));
    final result = FlutterStructureInspector.inventory(archive);
    expect(result['assetCount'], 0);
    expect(result['partial'], true);
  });
}
