# Phase 33 classic IL2CPP 27/29 metadata rows

Framework Binary Inspector checks the classic 31 offset/size pairs and
non-overlap, then samples up to 200 type definitions (88 bytes) and 300 method
definitions (32 bytes) for versions 27/29. Bounded metadata string resolution,
token-kind and declaring-type/method ownership checks are required. Unsupported
variants are reported unresolved rather than guessed. No native method address
resolution, managed IL, original C#, or method body reconstruction. Tests use
synthetic layout fixtures. Real Unity files need validation.
Layout reference:
https://github.com/Perfare/Il2CppDumper/blob/master/Il2CppDumper/Il2Cpp/MetadataClass.cs
