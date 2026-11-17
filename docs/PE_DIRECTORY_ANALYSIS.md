# PE directory analysis

Universal Binary Inspector → Open a PE32/PE32+ EXE or DLL → expand header
evidence → directoryAnalysis. All analysis is static and local.

- Standard import directory: DLL names, named imports with hint, and ordinal
  imports; 128 descriptors and 2,048 total symbols. Bound IAT without lookup
  data remains partial. No delay imports or runtime DLL loading.
- Export directory: names, ordinals, unused address holes and forwarder
  strings; first 2,048 functions and names. No code/function validation.
- CLR directory: header, metadata RVA/size, BSJB signature, bounded runtime
  version string and flags. No assembly table or IL decompilation.
- RVA translation requires unique file-backed section range, not zero-filled
  bytes or PE header ranges. Malformed tables report unresolved independently.

Synthetic tests exercise PE32/PE32+, ordinals, forwarders, CLR and invalid
ranges. The 32 MiB file limit remains. Real executable corpus validation
is pending. No Authenticode or runtime dependency verification.

Reference: https://learn.microsoft.com/en-us/windows/win32/debug/pe-format
