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

/// Two encoded elements with a string and an array of int/boolean values.
/// Reuses the same annotation set for class, method and parameter targets.
Uint8List makeDexWithAnnotationValues({bool invalidValue = false}) {
  final bytes = makeDexWithAnnotationTypes();
  bytes[9062] = 2; // elements_size
  bytes[9063] = 1; // name_idx: method0
  bytes[9064] = 0x17; // VALUE_STRING
  bytes[9065] = 2; // string_idx: method1
  bytes[9066] = 3; // name_idx: method2
  bytes[9067] = invalidValue ? 0xff : 0x1c; // VALUE_ARRAY
  bytes[9068] = 2; // array count
  bytes[9069] = 0x04; // VALUE_INT
  bytes[9070] = 42;
  bytes[9071] = 0x3f; // VALUE_BOOLEAN true
  return bytes;
}
