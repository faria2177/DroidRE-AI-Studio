import 'dart:typed_data';

import 'many_methods_fixture.dart';

/// DEX with a class that has a superclass, interface, source file, and fields.
///
/// Layout reuses the existing 205-method fixture, moving class_data after
/// the string data to prevent overlapping regions in malformed test samples.
Uint8List makeClassMetadataDex() {
  final bytes = makeManyMethodsDex();
  final data = ByteData.sublistView(bytes);

  void u16(int at, int value) =>
      data.setUint16(at, value, Endian.little);
  void u32(int at, int value) =>
      data.setUint32(at, value, Endian.little);

  // Five extra strings: two types, two field names, one source file.
  u32(56, 211);
  u32(64, 3); // DEX type_id_items at byte offset 1000.
  u32(80, 2); // Two field_ids.
  u32(84, 960);
  var stringAt = 10800;
  void string(int id, String value) {
    final chars = value.codeUnits;
    u32(112 + id * 4, stringAt);
    bytes[stringAt++] = chars.length;
    bytes.setRange(stringAt, stringAt + chars.length, chars);
    stringAt += chars.length;
    bytes[stringAt++] = 0;
  }
  string(206, 'I');
  string(207, 'Ljava/lang/Object;');
  string(208, 'counter');
  string(209, 'isReady');
  string(210, 'Many.java');
  u32(1004, 206); // I
  u32(1008, 207); // Ljava/lang/Object;

  // Field IDs: (owner class, type, field name).
  u16(960, 0);
  u16(962, 1);
  u32(964, 208);
  u16(968, 0);
  u16(970, 1);
  u32(972, 209);

  // Class definition metadata.
  u32(2908, 2); // superclass: java.lang.Object
  u32(2912, 1050); // type_list for implements.
  u32(2916, 210); // source_file_idx
  u32(2924, 8000); // class_data_off (moved to safe location)
  u32(1050, 1);
  u16(1054, 2);

  // class_data: 1 static field, 1 instance field, 0 direct methods,
  // 205 virtual methods. Fields use index deltas 0 and 1.
  bytes.setRange(8000, 8009, [
    1, 1, 0, 0xcd, 0x01, // class_data header
    0, 0x19, // field ID 0: public static final
    1, 0x02, // field ID 1: private
  ]);
  var at = 8009;
  for (var i = 0; i < 205; i++) {
    bytes[at++] = i == 0 ? 0 : 1;
    bytes[at++] = 0x81;
    bytes[at++] = 0x08;
    bytes[at++] = 0;
  }
  return bytes;
}
