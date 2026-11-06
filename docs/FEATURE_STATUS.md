# Feature status — 0.1.0

Do not mistake a visible tool card for a completed reverse-engineering engine.

| Feature | Status | Notes |
| --- | --- | --- |
| Flutter UI / navigation | Implemented | Material 3 dark UI, mobile and large screen layout |
| APK/ZIP import | Implemented | Uses user-selected documents and app-private copies |
| XAPK/APKS/APKM/AAB | Limited | Lists outer ZIP contents only; split decoding not yet available |
| SHA-256 / file inventory | Implemented | Archive entry list is capped at 10,000 for UI |
| AndroidManifest | Limited | Common binary XML/text attributes, not full resource resolution |
| DEX files | Inventory only | No class/method parsing, Smali or Java decompilation yet |
| Native `.so` | Inventory only | No ELF symbol decoding/disassembly yet |
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

- This MVP provides **real APK archive and manifest inspection**, not full source recovery.
- Large archives are inspected with streaming ZIP structures, but extracting the
  manifest can still use up to 4 MiB. Files over 1 GiB are refused.
- APK signature verification is **not yet implemented**.
- Some Android XML manifests refer to compiled resources that are not resolved yet.
- No cloud upload of APKs. AI only receives user-entered prompt text.
- Google account selection is not a substitute for server-side token verification.
- Test release-mode APKs use a temporary debug signing identity, not a trusted
  production keystore.
