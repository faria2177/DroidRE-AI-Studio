# Phases 31–33 — version evidence

Flutter AOT dialog now compares observed candidate hash against a manually supplied
trusted SDK hash. No built-in SDK database, object-pool decoder or Dart reconstruction.
Hermes inspector reports whether the header version is declared supported by the
original hbctool (59/62/74/76); the Windows helper refuses other versions rather than
guess opcodes. External disassembly remains separate. No built-in JS pseudocode.
Unity classic metadata prefix inspector maps up to 200 indexed string literals
(length/dataIndex) with range checks, UTF-8 replacement preview and clipping.
It does not infer type/method/native registration or C# source. External
Il2CppDumper remains optional. Real compiled fixture validation pending.
References:
https://github.com/bongtrop/hbctool
https://github.com/Perfare/Il2CppDumper/blob/master/Il2CppDumper/Il2Cpp/Metadata.cs
