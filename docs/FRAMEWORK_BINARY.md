# Framework Binary Inspector

Tools → Framework Binary Inspector → choose an indexed member.
Android and Windows share the local read-only engine. Up to 32 MiB per
member, 200 displayed candidates, 1 MiB raw string scan and 500 excerpts.

- Hermes execution magic and common header prefix: version, declared byte
  length, source hash bytes and count fields. No instruction or string
  table decoding. Header hash is not verified. Raw ASCII evidence is heuristic.
- IL2CPP metadata magic/version; classic prefix ranges for versions 24, 27,
  29, with range/overlap checks and bounded null-terminated ASCII name hints.
  No complete metadata schema, type tables, registration mapping or C# recovery.
- React Native bundle: strict UTF-8 text preview when not recognized as Hermes.
- NativeScript assets/app JS and JSON: text preview and bounded package.json
  declared dependency names. Not installed dependency/version verification.

No external binaries required, no code execution, no network requests.
Reports include SHA-256 of inspected member, scope labels and JSON export.
Real-world samples and version-specific format tests remain necessary.
Format references: https://github.com/facebook/hermes/blob/static_h/include/hermes/BCGen/HBC/BytecodeFileFormat.h
and https://github.com/IL2CPP-Toolkit/Core/blob/main/Metadata/Extraction/Il2Cpp/MetadataClass.cs .
