import 'dart:typed_data';

import 'many_methods_fixture.dart';

/// One real code_item added to the 205-method DEX fixture. Its last method
/// has a const-string, an invoke-static, one try_item, a typed exception
/// handler and a catch-all handler.
Uint8List makeDexWithTryAndReferences({
  bool brokenHandlerOffset = false,
  bool brokenCatchAddress = false,
  bool brokenOpcode = false,
}) {
  final bytes = makeManyMethodsDex();
  final view = ByteData.sublistView(bytes);
  void u16(int at, int value) =>
      view.setUint16(at, value, Endian.little);
  void u32(int at, int value) =>
      view.setUint32(at, value, Endian.little);

  // Class_data originally contains 205 virtual methods. Method #204 is
  // the last encoded entry: index delta (1), flags and code_off ULEB.
  const last = 3005 + 204 * 4;
  bytes[last + 1] = 0x81; // public accessFlags, two-byte ULEB
  bytes[last + 2] = 0;
  bytes[last + 3] = 0x80; // code_off: 8192 (two-byte ULEB)
  bytes[last + 4] = 0x40;

  const code = 8192;
  u16(code, 1); // registers
  u16(code + 2, 0); // ins
  u16(code + 4, 0); // outs
  u16(code + 6, 1); // tries_size
  u32(code + 8, 0); // debug_info_off
  u32(code + 12, 6); // insns_size, code units
  u16(code + 16, brokenOpcode ? 0x00f0 : 0x001a);
  u16(code + 18, 1); // const-string index1: method0
  u16(code + 20, 0x1071); // invoke-static {v0}, method200
  u16(code + 22, 200);
  u16(code + 24, 0);
  u16(code + 26, 0x000e); // return-void

  const triesAt = code + 16 + 12;
  u32(triesAt, 0); // start_addr
  u16(triesAt + 4, 5); // insn_count, ending before return
  u16(triesAt + 6, brokenHandlerOffset ? 9 : 1);
  // encoded_catch_handler_list: size=1, handler at relative +1.
  final handlers = triesAt + 8;
  bytes[handlers] = 1;
  bytes[handlers + 1] = 0x7f; // sleb -1: one typed + catchall
  bytes[handlers + 2] = 0; // type_idx 0: Lcom/demo/Many;
  bytes[handlers + 3] = brokenCatchAddress ? 9 : 5;
  bytes[handlers + 4] = 5;
  return bytes;
}
