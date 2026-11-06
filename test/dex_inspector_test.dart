import 'dart:convert';
import 'dart:typed_data';

import 'package:droidre_ai_studio/services/dex_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List makeDex() {
  final bytes = Uint8List(320);
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
  u32(72, 1); // method prototypes
  u32(76, 164);
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
  u32(164, 1); // shorty_idx (unused by this basic inspector)
  u32(168, 0); // return_type_idx
  u32(172, 0); // no parameter list
  final classDescriptor = ascii.encode('Lcom/demo/Example;');
  bytes[180] = classDescriptor.length;
  bytes.setRange(181, 181 + classDescriptor.length, classDescriptor);
  final method = ascii.encode('run');
  bytes[220] = method.length;
  bytes.setRange(221, 224, method);
  bytes.setRange(250, 258, [0, 0, 1, 0, 0, 1, 0x98, 0x02]);
  data.setUint16(280, 2, Endian.little); // registers_size
  u32(292, 1); // insns_size in 16-bit code units
  data.setUint16(296, 0x000e, Endian.little); // return-void
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
    final detail = result.classes.single.details.single;
    expect(detail.prototype, '()Lcom/demo/Example;');
    expect(detail.codeOffset, 280);
    expect(detail.smaliPreview, contains('return-void'));
    expect(detail.smaliPreview, contains('.registers 2'));
    final decoded = DexInspector.disassembleMethodBytes(makeDex(), detail);
    expect(decoded, contains('0000: return-void'));
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

  test('rejects code item beyond DEX bounds', () {
    final bytes = makeDex();
    ByteData.sublistView(bytes).setUint32(292, 100000, Endian.little);
    expect(() => DexInspector.inspectBytes(bytes), throwsFormatException);
  });
}
