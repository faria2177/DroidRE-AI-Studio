# Feature status — 0.3.0

Do not mistake a visible tool card for a completed reverse-engineering engine.

| Feature | Status | Notes |
| --- | --- | --- |
| Flutter UI / navigation | Implemented | Material 3 dark UI, mobile and large screen layout |
| APK/ZIP import | Implemented | Uses user-selected documents and app-private copies |
| XAPK/APKS/APKM/AAB | Limited | Lists outer ZIP contents only; split decoding not yet available |
| SHA-256 / file inventory | Implemented | Archive entry list is capped at 10,000 for UI |
| AndroidManifest | Limited | Common binary XML/text attributes, not full resource resolution |
| DEX files | Basic inspector + method details | DEX 035–040 class/method names, prototypes, flags, registers, raw code units (first 64); no instruction operand decoding |
| Smali preview | Limited | Read-only, non-assemblable, hex code-unit view and opcode-name hints, not full Smali |
| APK Resources | Basic explorer | `res/`, `assets/`, `resources.arsc` package names, small text/image/hex previews |
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
- DEX method names/prototype descriptors are decoded, but raw instructions are not
  fully disassembled. Modified UTF-8 and unsupported DEX versions may not be fully decoded.
- Method previews include prototypes and up to 64 raw 16-bit code units;
  **opcode names are only hints**, not correct instruction boundaries/operands.
  Method detail previews are bounded to 20,000 per DEX file.
- Resource table parsing is header-only (package names/counts); resource values,
  IDs, binary XML UI trees and decoded drawables are not yet resolved.
- Individual DEX files over 32 MiB and native libraries over 80 MiB are rejected.
- Some Android XML manifests refer to compiled resources that are not resolved yet.
- No cloud upload of APKs. AI only receives user-entered prompt text.
- Google account selection is not a substitute for server-side token verification.
- Test release-mode APKs use a temporary debug signing identity, not a trusted
  production keystore.
