import 'dart:typed_data';

import 'method_semantics_fixture.dart';

/// Synthetic DEX debug_info_item for the final method (method204).
/// The DEX code_item is at byte offset 8192; debug_info is at 9200.
/// Line numbers, parameter names, locals and source-file changes all use
/// real DEX state-machine bytecode, not mocked inspector output.
Uint8List makeDexWithDebugInfo({
  bool badParameterCount = false,
  bool badRegister = false,
  bool brokenStringIndex = false,
  bool omitEnd = false,
  bool badAddress = false,
}) {
  final bytes = makeDexWithTryAndReferences();
  final view = ByteData.sublistView(bytes);
  void u16(int at, int value) =>
      view.setUint16(at, value, Endian.little);
  void u32(int at, int value) =>
      view.setUint32(at, value, Endian.little);

  // The existing code item has six 16-bit instructions and one try range.
  // Give it three registers and two declared (non-receiver) parameters.
  u16(8192, 3);
  u16(8194, 2);
  u32(8200, 9200); // debug_info_off in code_item
  u32(2808, 9100); // parameters_off in proto_id_item
  u32(9100, 2); // two type_list_item entries
  u16(9104, 0);
  u16(9106, 0);

  // line_start=100; two parameters names method1, method2 (string IDs 2,3).
  // v0 local: method3, class type; v1 extended local: method4, signature
  // method5; later DBG_SET_FILE -> method6.
  final info = <int>[
    100,
    badParameterCount ? 1 : 2,
    3,
    if (!badParameterCount) 4,
    0x03, badRegister ? 9 : 0,
    brokenStringIndex ? 0xff : 5, 1,
    if (brokenStringIndex) 0x7f,
    0x01, 1, // DBG_ADVANCE_PC -> 1
    0x02, 2, // DBG_ADVANCE_LINE -> 102
    0x07, // DBG_SET_PROLOGUE_END
    0x0e, // special: delta pc=0, delta line=0 -> emit (1,102)
    0x04, 1, 6, 1, 7, // local_extended(v1,method4, type, sig method5)
    0x01, 1, // DBG_ADVANCE_PC -> 2
    0x05, 0, // DBG_END_LOCAL(v0)
    0x01, badAddress ? 9 : 1, // -> 3 or past method
    0x06, 0, // DBG_RESTART_LOCAL(v0)
    0x09, 8, // DBG_SET_FILE(method6)
    0x08, // DBG_SET_EPILOGUE_BEGIN
    0x1d, // special: advance pc=1, line delta=0 -> (4,102)
    if (!omitEnd) 0x00, // DBG_END_SEQUENCE
  ];
  bytes.setRange(9200, 9200 + info.length, info);
  // Missing END_SEQUENCE fixtures must force a bounded read failure,
  // not accidentally find trailing zero in the large DEX allocation.
  if (omitEnd) {
    bytes.fillRange(9200 + info.length, bytes.length, 0x01);
  }
  return bytes;
}
