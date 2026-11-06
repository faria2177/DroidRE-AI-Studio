import 'dart:convert';
import 'dart:typed_data';

import 'package:droidre_ai_studio/services/dex_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List makeDex() {
  final bytes = Uint8List(300);
  final data = ByteData.sublistView(bytes);
  void u32(int offset, int value) => data.setUint32(offset, value, Endian.little);
  final magic = ascii.encode('dex\n035\x00');
  bytes.setRange(0, magic.length, magic);
  u32(32, bytes.length);
  u32(36, 112);
  u32(40, 0x12345678);
  u32(56, 2); // strings
  u32(60, 112);
  u32(64, 1); // types
  u32(68, 120);
  u32(88, 1); // method_ids
  u32(92, 124);
  u32(96, 1); // class_defs
  u32(100, 132);
  u32(112, 180);
  u32(116, 220);
  u32(120, 0); // type descriptor string index
  u32(128, 1); // method name string index
  u32(132, 0); // class type index
  u32(136, 1); // public class
  u32(156, 250); // class_data_off
  final classDescriptor = ascii.encode('Lcom/demo/Example;');
  bytes[180] = classDescriptor.length;
  bytes.setRange(181, 181 + classDescriptor.length, classDescriptor);
  final method = ascii.encode('run');
  bytes[220] = method.length;
  bytes.setRange(221, 224, method);
  bytes.setRange(250, 257, [0, 0, 1, 0, 0, 1, 0]);
  return bytes;
}

void main() {
  test('extracts DEX class and method identifiers', () {
    final result = DexInspector.inspectBytes(makeDex());
    expect(result.version, '035');
    expect(result.classes, hasLength(1));
    expect(result.classes.single.name, 'com.demo.Example');
    expect(result.classes.single.methods, ['run']);
    expect(result.classes.single.methodCount, 1);
  });

  test('rejects corrupt DEX table offset', () {
    final bytes = makeDex();
    ByteData.sublistView(bytes).setUint32(100, 9999, Endian.little);
    expect(() => DexInspector.inspectBytes(bytes), throwsFormatException);
  });

  test('rejects invalid and truncated DEX files', () {
    expect(() => DexInspector.inspectBytes(Uint8List(20)), throwsFormatException);
    final bytes = makeDex();
    bytes[0] = 0;
    expect(() => DexInspector.inspectBytes(bytes), throwsFormatException);
  });
}
