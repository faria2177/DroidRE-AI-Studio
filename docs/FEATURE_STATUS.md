# Feature status — 0.4.0

Do not mistake a visible tool card for a completed reverse-engineering engine.

| Feature | Status | Notes |
| --- | --- | --- |
| Flutter UI / navigation | Implemented | Material 3 dark UI, mobile and large screen layout |
| APK/ZIP import | Implemented | Uses user-selected documents and app-private copies |
| XAPK/APKS/APKM/AAB | Limited | Lists outer ZIP contents only; split decoding not yet available |
| SHA-256 / file inventory | Implemented | Archive entry list is capped at 10,000 for UI |
| AndroidManifest | Limited | Common binary XML/text attributes, not full resource resolution |
| DEX files | Basic inspector + method details | DEX 035–040 class/method names, prototypes, flags, registers and first 64 raw code units as fallback |
| Dalvik instructions | Implemented for standard opcodes | On-demand DEX 035–040 opcode, operands, register/branch decoding and switch/array payload boundaries; not verified Smali |
| Smali preview | Read-only | Code offset/descriptor and decoded instructions; not Java reconstruction or round-trip Smali assembly |
| APK Resources | XML viewer | `res/`, `assets/`, `resources.arsc` package names, text/image/hex previews and binary XML hierarchy |
| AI code explanations | Opt-in integrated | Select method/XML → review prefilled prompt → consent → send to chosen provider; no binary APK upload |
| Native `.so` | Basic ELF inspector | On-demand ELF32/ELF64 headers, architecture, byte order and counts; no symbols/disassembly |
| Framework detection | Heuristic | Shows indicators, not certainty |
| Project persistence | Implemented | Local copied artifacts and JSON index |
| Google account button | Needs OAuth setup | Account chooser code exists; backend auth verification is future work |
| OpenRouter/OpenAI/DeepSeek/Groq AI | Working API adapter design | Requires a valid user API key/model and network; no secrets persisted |
| AI model catalog / fallback | Planned | No automatic switching claimed |
| Security audit / version diff | Planned | UI links explicitly labeled roadmap |
| Smali edit/rebuild/sign | Planned | Only authorized editing will be supported |
| Local LLM / optional worker | Planned | Separate opt-in architecture |
| GitHub CI / APK workflows | Implemented as workflow definitions | Actual result depends on Actions run |

## Known limitations

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
- Method detail previews in the class list are bounded to 20,000 per DEX file.
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
- Test release-mode APKs use a temporary debug signing identity, not a trusted
  production keystore.
