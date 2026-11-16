import 'dart:convert';
import 'dart:typed_data';

import 'package:droidre_ai_studio/services/dex_inspector.dart';
import 'package:droidre_ai_studio/services/dex_method_pager.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List makeManyMethodsDex() {
  const methodCount = 205;
  final bytes = Uint8List(12000);
  final data = ByteData.sublistView(bytes);
  void u32(int at, int value) => data.setUint32(at, value, Endian.little);

  bytes.setRange(0, 8, ascii.encode('dex\n035\x00'));
  u32(32, bytes.length);
  u32(36, 112);
  u32(40, 0x12345678);
  u32(56, methodCount + 1); // string IDs
  u32(60, 112);
  u32(64, 1); // type IDs
  u32(68, 1000);
  u32(72, 1); // prototype IDs
  u32(76, 2800);
  u32(88, methodCount);
  u32(92, 1100);
  u32(96, 1); // class defs
  u32(100, 2900);

  u32(1000, 0); // class descriptor string ID
  u32(2800, 0); // shorty string
  u32(2804, 0); // return type
  u32(2808, 0); // no parameters
  u32(2900, 0); // class type
  u32(2904, 0x401); // abstract public
  u32(2924, 3000); // class_data_off

  var stringAt = 4000;
  void writeString(int id, String value) {
    final string = ascii.encode(value);
    u32(112 + id * 4, stringAt);
    bytes[stringAt++] = string.length;
    bytes.setRange(stringAt, stringAt + string.length, string);
    stringAt += string.length;
    bytes[stringAt++] = 0;
  }
  writeString(0, 'Lcom/demo/Many;');
  for (var i = 0; i < methodCount; i++) {
    writeString(i + 1, 'method$i');
    final at = 1100 + i * 8;
    data.setUint16(at, 0, Endian.little); // defining class
    data.setUint16(at + 2, 0, Endian.little); // prototype
    u32(at + 4, i + 1); // method name
  }

  // No fields/direct methods, 205 virtual abstract methods.
  bytes.setRange(3000, 3005, [0, 0, 0, 0xcd, 0x01]);
  var at = 3005;
  for (var i = 0; i < methodCount; i++) {
    bytes[at++] = i == 0 ? 0 : 1; // method_idx_diff
    bytes[at++] = 0x81; // flags ULEB128 (public abstract)
    bytes[at++] = 0x08;
    bytes[at++] = 0; // code_off absent for abstract methods
  }
  return bytes;
}

void main() {
  test('loads methods after the initial 200-method preview', () {
    final bytes = makeManyMethodsDex();
    final klass = DexInspector.inspectBytes(bytes).classes.single;
    expect(klass.classDefIndex, 0);
    expect(klass.methodCount, 205);
    expect(klass.details, hasLength(200));

    final next = DexMethodPager.loadBytes(bytes, klass, start: 200, limit: 3);
    expect(next.map((method) => method.name).toList(), [
      'method200', 'method201', 'method202',
    ]);
    expect(next.map((method) => method.methodIdIndex).toList(), [200, 201, 202]);
    expect(next.first.ownerName, 'com.demo.Many');
    expect(DexMethodPager.loadBytes(bytes, klass, start: 204), hasLength(1));
    expect(DexMethodPager.loadBytes(bytes, klass, start: 205), isEmpty);
  });

  test('rejects stale class IDs and invalid page windows', () {
    final bytes = makeManyMethodsDex();
    final klass = DexInspector.inspectBytes(bytes).classes.single;
    expect(() => DexMethodPager.loadBytes(bytes, klass, start: -1),
        throwsFormatException);
    expect(() => DexMethodPager.loadBytes(bytes, klass, limit: 201),
        throwsFormatException);
    expect(() => DexMethodPager.loadBytes(bytes, klass, start: 206),
        throwsFormatException);
    final stale = Uint8List.fromList(bytes);
    ByteData.sublistView(stale).setUint32(2900, 2, Endian.little);
    expect(() => DexMethodPager.loadBytes(stale, klass),
        throwsFormatException);
  });
}
