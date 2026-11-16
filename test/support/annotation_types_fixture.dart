import 'dart:typed_data';

import 'many_methods_fixture.dart';

/// Minimal DEX annotation_directory_item: one class, method204 and
/// parameter0 annotation all referring to the same type-only annotation set.
Uint8List makeDexWithAnnotationTypes({bool invalidSet = false}) {
  final bytes = makeManyMethodsDex();
  final view = ByteData.sublistView(bytes);
  void u32(int at, int value) =>
      view.setUint32(at, value, Endian.little);

  u32(2900 + 20, 9000); // class_def.annotations_off
  u32(9000, invalidSet ? 11999 : 9050); // class_annotations_off
  u32(9004, 0); // fields_size
  u32(9008, 1); // annotated_methods_size
  u32(9012, 1); // annotated_parameters_size
  u32(9016, 204); // method_idx
  u32(9020, 9050); // annotation_set
  u32(9024, 204); // parameter owner method_idx
  u32(9028, 9090); // annotation_set_ref_list
  u32(9050, 1); // annotation_set.size
  u32(9054, 9060); // annotation_item_off
  bytes[9060] = 1; // VISIBILITY_RUNTIME
  bytes[9061] = 0; // annotation type_idx=0 -> Lcom/demo/Many;
  bytes[9062] = 0; // encoded element_count=0
  u32(9090, 1); // one parameter slot
  u32(9094, 9050);
  return bytes;
}
