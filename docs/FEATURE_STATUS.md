# Feature status — 0.7.0

Do not mistake a visible tool card for a completed reverse-engineering engine.

| Feature | Status | Notes |
| --- | --- | --- |
| Flutter UI / navigation | Implemented | Material 3 dark UI, mobile and large screen layout |
| APK/ZIP import | Implemented | Uses user-selected documents and app-private copies |
| XAPK/APKS/APKM/AAB | Limited | Lists outer ZIP contents only; split decoding not yet available |
| SHA-256 / file inventory | Implemented | Archive entry list is capped at 10,000 for UI |
| AndroidManifest | Limited | Common binary XML/text attributes, not full resource resolution |
| DEX files | Basic inspector + on-demand method pages | DEX 035–040 class/method names, prototypes, flags, registers and first 64 raw code units as fallback; load later methods in 100-method pages |
| Dalvik instructions | Implemented for standard opcodes | On-demand DEX 035–040 opcode/operand decoding, switch/array payload links, source-relative switch-case targets and bounded branch diagnostics; not verified Smali |
| DEX symbols | Partial resolution | Resolve string/type/prototype/method/field identifiers to descriptors; call-site and method-handle internals remain symbolic |
| Cross-reference navigation | Bounded method XREFs | Browse outgoing referenced methods and scan indexed method bodies for incoming callers; not a complete whole-APK call graph |
| Multi-DEX call graph | Static, bounded | Prioritizes the selected DEX and scans up to 24 DEX files, 6,000 method bodies and 1.5 million code units; matches method signatures across DEX files and displays direct and two-hop calls |
| Java-like pseudocode | Approximate viewer | Converts common Dalvik instructions into Java-like annotated statements with original PC; not a real Java decompiler |
| Smali preview | Read-only | Code offset/descriptor and decoded instructions; not Java reconstruction or round-trip Smali assembly |
| On-device source folders, DEX semantics and debug info | SAF-based File Manager folder + bounded recovery (unverified) | Framework-aware source preview with up to 3 DEX / 80 classes / 400 methods / 32 resources, class hierarchy/fields, annotation types and bounded encoded values (no runtime evaluation), try/catch handlers and instruction references. New per-class `method_debug_info.json`: DEX debug parameter names, source-line mappings, source-file switches, prologue/epilogue flags and local-variable lifetimes. Debug streams bounded (128 KiB / 5,000 opcodes / 512 positions / 256 local ranges / 255 parameters); missing/malformed debug data is not fabricated; partial status reported. Java-like/Dalvik previews are non-compilable and non-assemblable. See the latest CI run for build/test status. |
| APK Resources | Advanced configuration filters, reference ID diffs, CSV/JSON export and inherited styles | Up to 250 decoded `resources.arsc` entries, packed language/region + BCP-47 script/variant preview, night/density/orientation/SDK qualifiers, variant filters (changed, night/day, localized, density, raw reference changes), read-only scalar and bounded bag/attribute diffs. Configuration comparison export includes baseline/variants, raw and reference changes, partial/truncated diagnostics in JSON or UTF-8 CSV (formula-escaped for spreadsheet safety), saved through user-selected file dialog. No Android runtime resource selection, remapping of dynamic references, overlay resolution or full theme rendering. |
| AI code explanations | Opt-in integrated | Method prompts include resolved symbols and instruction-offset evidence requests; review/edit prompt → consent → send to chosen provider; no binary APK upload |
| Native `.so` | ELF sections, paged hex preview and dependency graph | On-demand ELF32/ELF64 sections (up to 1,024), read-only Hex/ASCII preview in 256-byte pages for file-backed sections, symbols/imports/exports, `DT_NEEDED` and SONAME, RPATH/RUNPATH; same-ABI dependency graph (up to 64 libraries). NOBITS sections have no hex; partial ARM64 linear disassembly available; no runtime linkage verification |
| Framework detection | Heuristic | Shows indicators, not certainty |
| Project persistence | Implemented | Local copied artifacts and JSON index |
| Google account button | Requires Google OAuth registration | Configurable Web Client ID in Settings, native account selection/restore; package name + APK signing SHA must be registered, backend auth verification is future work |
| OpenRouter/OpenAI/DeepSeek/Groq AI | Working API adapter design | Requires a valid user API key/model and network; no secrets persisted |
| AI model catalog / fallback | Planned | No automatic switching claimed |
| Security audit / version diff | Planned | UI links explicitly labeled roadmap |
| Smali edit/rebuild/sign | Planned | Only authorized editing will be supported |
| Local LLM / optional worker | Planned | Separate opt-in architecture |
| GitHub CI / APK workflows | Implemented as workflow definitions | Actual result depends on Actions run |

## Large APK preview windows

ZIP export accepts a zero-based DEX:class:method cursor and reports a next
cursor for continuation at bounded export limits. Automatic folder recovery
still exports the first window only; malformed or oversized inputs may be skipped.

## Normal-flow basic blocks

Method disassembly and recovered Dalvik previews now include bounded basic
blocks, conditional/goto/switch successors, normal-flow reachability and
backward-edge hints. Payload data is excluded from execution. The graph
caps switch edges at 4,096, displays up to 128 blocks and 20 edges per
block, and marks incomplete or invalid targets. Exception edges, type
verification and semantic loop detection are not included.

## Java-like statement reconstruction

The viewer preserves instruction offsets and register names, renders comparison
operators, two-address and literal arithmetic, array access, instance-field
receivers and allocation without inventing constructors. Invoke/filled-array
results are linked only to adjacent move-result instructions within a complete
normal-flow graph and outside branch entries. Unresolved results stay explicit.
This is not SSA, type inference, structured loops or compilable Java.

## Resource recovery index

Source ZIP includes a read-only compiled table and XML-reference sidecar.
Known-name hints never overwrite original XML IDs; dynamic, unavailable or
ambiguous targets are explicit. The table reader is bounded to 250 values,
40 MiB of input and 200,000 scanned slots. This is not a rebuildable resource tree.

## Native ARM64 disassembly preview

128 instructions per page, restricted to executable file-backed PROGBITS
sections of little-endian AArch64 ELF shared objects/executables. Sized FUNC
symbols can open a range only within their declared section. Branches, returns,
selected arithmetic/address/load-store instructions decode; other words remain
explicitly unsupported. No relocation, data-vs-code certainty, inferred function
bounds, ARM32/x86 decoding, or native decompilation.

## Flutter AOT snapshot evidence

ELF Explorer now maps legacy VM/isolate snapshot symbols and consolidated
Dart snapshot data/text/build-ID symbols. Exact-name filtering scans up to
100,000 symbol records, rather than relying on the first 500 named symbols.
Bounded raw header samples and data signature evidence are mapped to file
and virtual addresses. No snapshot object deserialization, inferred symbol
locations, version matching, or original Dart source recovery.

## Known limitations

- The source recovery ZIP produces non-compilable/non-assemblable text previews only. See `docs/SOURCE_RECOVERY.md` for bounds, privacy, and omitted source types.


- This milestone provides **real APK archive/manifest and bounded DEX/ELF header inspection**, not full source recovery.
- Large archives are inspected with streaming ZIP structures, but extracting the
  manifest can still use up to 4 MiB. Files over 1 GiB are refused.
- APK signature verification is **not yet implemented**.
- DEX method names and prototype descriptors are decoded. Standard Dalvik opcode
  operands are decoded; advanced/optimized instructions and semantic analysis
  remain incomplete. Modified UTF-8 may not be fully decoded.
- The first 64 raw code units remain available as a fallback, while selected
  methods decode on demand up to 100,000 code units and display up to 20,000
  instructions. Reserved, optimized/odex and unknown opcodes stop disassembly
  without guessing instruction boundaries. No semantic type/control-flow verification.
- Initial method detail previews are bounded to 20,000 per DEX file, with up to 200 names/details per class. Additional class method details can be loaded on demand in 100-method pages. Case-insensitive declared-method name search scans the selected DEX on demand, with a 200-result / 250,000-method limit and explicit partial-result warnings. This does not remove the existing XREF or call-graph scan limits.
- Incoming XREF scans inspect at most 5,000 indexed methods / 1,000,000 code units and list at most 100 matches. Unsupported Dalvik code is skipped and a count shown; references outside the selected DEX, missing or unindexed methods, and virtual dispatch remain unresolved.
- Multi-DEX scan is **not** a full call graph: it prioritizes the selected DEX, inspects at most 24 DEX files / 6,000 indexed methods / 1,500,000 code units and records up to 18,000 unique static invocation edges. Reflection, JNI calls, dynamically loaded DEX, virtual dispatch targets and code beyond bounds remain unresolved.
- Java-like pseudocode is approximate and not compilable. It preserves Dalvik registers, original offsets and comments for instructions it cannot translate.
- Resource table parsing is header-only (package names/counts); resource values,
  IDs and decoded drawables are not yet resolved. Binary XML element and
  attribute names are decoded, but IDs and complex typed values remain symbolic.
- Selected code may contain proprietary content or secrets; users must review
  and explicitly consent before sharing the prompt with an AI provider.
- Individual DEX files over 32 MiB and native libraries over 80 MiB are rejected.
- Some Android XML manifests refer to compiled resources that are not resolved yet.
- No cloud upload of APKs. AI only receives the prompt text users review and
  explicitly send, including selected snippets when they consent.
- Google account selection is not a substitute for server-side token verification.
- Google account selection will not work in APKs whose signing SHA is not registered in Google Cloud. GitHub-hosted debug APK signing keys can change between workflow runs. See `docs/GOOGLE_SIGN_IN_SETUP.md`.
- Test release-mode APKs use a temporary debug signing identity, not a trusted
  production keystore.
