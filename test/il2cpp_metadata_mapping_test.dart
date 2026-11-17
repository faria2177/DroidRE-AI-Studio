import 'dart:typed_data';
import 'package:droidre_ai_studio/services/il2cpp_metadata_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classic metadata maps methods to declaring type and names', () {
    final bytes = Uint8List(512);
    final d = ByteData.sublistView(bytes);
    void u32(int at, int v) => d.setUint32(at, v, Endian.little);
    u32(0, 0xfab11baf); u32(4, 29);
    u32(24, 256); u32(28, 32);
    u32(48, 288); u32(52, 32);
    u32(160, 320); u32(164, 88);
    final strings = 'Demo\u0000Example\u0000Run\u0000'.codeUnits;
    bytes.setRange(256, 256 + strings.length, strings);
    u32(288, 13); u32(292, 0); u32(308, 0x06000001);
    d.setUint16(318, 2, Endian.little);
    u32(320, 0); u32(324, 5);
    u32(356, 0);
    d.setUint16(384, 1, Endian.little);
    u32(404, 0x02000001);
    final report = Il2cppMetadataMapping.inspect(bytes);
    final method = (report['methods'] as List).single as Map;
    expect(method['name'], 'Run');
    expect(method['declaringType'], 'Demo');
    expect(method['namespace'], 'Example');
    expect(method['parameterCount'], 2);
    u32(292, 9);
    expect((Il2cppMetadataMapping.inspect(bytes)['methods'] as List), isEmpty);
    u32(52, 31);
    expect(() => Il2cppMetadataMapping.inspect(bytes), throwsFormatException);
  });
}
