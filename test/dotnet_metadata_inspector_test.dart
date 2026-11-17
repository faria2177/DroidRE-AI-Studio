import 'dart:typed_data';

import 'package:droidre_ai_studio/services/dotnet_metadata_inspector.dart';
import 'package:droidre_ai_studio/services/ilspy_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List rootFixture() {
  final bytes = Uint8List(128);
  final d = ByteData.sublistView(bytes);
  void u32(int at, int value) => d.setUint32(at, value, Endian.little);
  u32(0, 0x424a5342);
  u32(12, 4);
  d.setUint16(22, 2, Endian.little);
  u32(24, 64);
  u32(28, 32);
  bytes.setRange(32, 34, '#~'.codeUnits);
  u32(36, 96);
  u32(40, 16);
  bytes.setRange(44, 52, '#Strings'.codeUnits);
  u32(72, (1 << 2) | (1 << 6));
  u32(88, 3);
  u32(92, 7);
  return bytes;
}

void main() {
  test('reads stream ranges and declared TypeDef/MethodDef counts', () {
    final bytes = rootFixture();
    final report = DotnetMetadataInspector.inspect(bytes, 0, bytes.length);
    expect((report['streams'] as List).length, 2);
    expect(report['tableRowCounts'], [
      {'tableId': 2, 'name': 'TypeDef', 'declaredRows': 3},
      {'tableId': 6, 'name': 'MethodDef', 'declaredRows': 7},
    ]);
  });

  test('rejects intersecting stream ranges and truncated row counts', () {
    final bytes = rootFixture();
    final d = ByteData.sublistView(bytes);
    d.setUint32(36, 80, Endian.little);
    expect(() => DotnetMetadataInspector.inspect(bytes, 0, bytes.length), throwsFormatException);
    d.setUint32(36, 96, Endian.little);
    d.setUint32(28, 24, Endian.little);
    expect(() => DotnetMetadataInspector.inspect(bytes, 0, bytes.length), throwsFormatException);
  });

  test('ILSpy mode arguments are explicit and disable update check', () {
    expect(IlspyRecovery.arguments('C:/demo app.dll', IlspyMode.il),
      ['--disable-updatecheck', '--ilcode', 'C:/demo app.dll']);
    expect(IlspyRecovery.arguments('C:/demo app.dll', IlspyMode.project, output: 'C:/out dir'),
      ['--disable-updatecheck', '--project', '--outputdir', 'C:/out dir', 'C:/demo app.dll']);
    expect(() => IlspyRecovery.arguments('source.dll', IlspyMode.project), throwsFormatException);
  });
}
