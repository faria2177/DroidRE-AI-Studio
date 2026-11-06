import 'dart:convert';
import 'dart:typed_data';

import 'package:droidre_ai_studio/services/android_binary_xml_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List sampleBinaryXml() {
  const strings = ['LinearLayout', 'text', 'Hello & <world>'];
  final stringBytes = <int>[];
  final stringOffsets = <int>[];
  for (final text in strings) {
    final encoded = utf8.encode(text);
    stringOffsets.add(stringBytes.length);
    stringBytes.addAll([text.length, encoded.length, ...encoded, 0]);
  }
  final poolSize = 28 + 4 * strings.length + stringBytes.length;
  final total = 8 + poolSize + 56 + 24;
  final bytes = Uint8List(total);
  final data = ByteData.sublistView(bytes);
  void u16(int at, int value) => data.setUint16(at, value, Endian.little);
  void u32(int at, int value) => data.setUint32(at, value, Endian.little);

  u16(0, 0x0003);
  u16(2, 8);
  u32(4, total);
  const pool = 8;
  u16(pool, 1);
  u16(pool + 2, 28);
  u32(pool + 4, poolSize);
  u32(pool + 8, strings.length);
  u32(pool + 16, 0x100);
  u32(pool + 20, 28 + 4 * strings.length);
  for (var i = 0; i < strings.length; i++) {
    u32(pool + 28 + i * 4, stringOffsets[i]);
  }
  bytes.setRange(pool + 28 + 4 * strings.length,
      pool + poolSize, stringBytes);

  final start = pool + poolSize;
  u16(start, 0x0102);
  u16(start + 2, 16);
  u32(start + 4, 56);
  u32(start + 16, 0xffffffff);
  u32(start + 20, 0); // root tag
  u16(start + 24, 20); // attributes relative to ext start
  u16(start + 26, 20);
  u16(start + 28, 1);
  u32(start + 36, 0xffffffff);
  u32(start + 40, 1); // attr name: text
  u32(start + 44, 2); // attr raw value: Hello ...
  u16(start + 48, 8);
  bytes[start + 51] = 3;
  u32(start + 52, 2);

  final end = start + 56;
  u16(end, 0x0103);
  u16(end + 2, 16);
  u32(end + 4, 24);
  u32(end + 16, 0xffffffff);
  u32(end + 20, 0);
  return bytes;
}

void main() {
  test('renders compiled XML element hierarchy and escaped attributes', () {
    final result = AndroidBinaryXmlDecoder.decode(sampleBinaryXml());
    expect(result.elements, 1);
    expect(result.attributes, 1);
    expect(result.xml, contains('<LinearLayout text="Hello &amp; &lt;world&gt;">'));
    expect(result.xml, contains('</LinearLayout>'));
  });

  test('refuses truncated compiled XML attributes', () {
    final bytes = sampleBinaryXml();
    final poolSize = ByteData.sublistView(bytes).getUint32(12, Endian.little);
    final start = 8 + poolSize;
    ByteData.sublistView(bytes).setUint16(start + 28, 999,
        Endian.little);
    expect(() => AndroidBinaryXmlDecoder.decode(bytes), throwsFormatException);
  });

  test('allows ordinary plain text XML without binary translation', () {
    final result = AndroidBinaryXmlDecoder.decode(Uint8List.fromList(
        utf8.encode('<TextView text="ok"/>')));
    expect(result.xml, contains('TextView'));
  });
}
