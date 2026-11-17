# Phase 30 — 0.8.0 development preview readiness

Do not label this version 1.0 production-ready. Phases are development workstreams,
not a percentage estimate of verified functionality.

| Phase | Implemented scope | Remaining gate |
| --- | --- | --- |
| 22 | Declaration hints, session bookmarks/history | Semantic index, persistent navigation, version history, device UI |
| 23 | Ranked multi-term local evidence and reviewed AI prompt | Embedding retrieval, genuine agent workflows, provider tests |
| 24 | Manual Ghidra function export script | Compile/run with installed Ghidra, integrated native CFG |
| 25 | Dart classic snapshot hash evidence | Version database, object pool, verified per-VM decoder |
| 26 | Framework member export and manual trusted recovery helper | Version-specific Hermes/IL2CPP recovery validation |
| 27 | Individual split APK export, previous Apktool and signing helpers | Split merge/rebuild/verification, Android signing |
| 28 | Bounded ADB refresh and app memory reports | Device integration, continuous streaming and debugger |
| 29 | Streaming raw binary pages/hash/search up to 1 GiB | Stress tests, fuzzing, complete security audit |
| 30 | Version bump, user manual and release checklist | Same-commit builds, install tests, owner signing, release publishing |

## Mandatory release gates

- [ ] Both latest-commit Android and Windows CI: format, analyze, all tests, artifacts.
- [ ] Android arm64 + armv7 test artifact and AAB on same source commit.
- [ ] Real Android 16 and supported older/32-bit device installation and UI.
- [ ] Windows 11 x64 installer, portable startup, uninstall, file access and resource measurements.
- [ ] Trusted external tool end-to-end checks (JADX, Apktool, LLVM, ILSpy, Ghidra, Hermes and IL2CPP).
- [ ] Malformed archives and binaries, path/symlink, resource budget, security and privacy review.
- [ ] Real provider model tests and Google OAuth registration for the production signing identity.
- [ ] Owner-supplied production Android keystore and Windows signing certificate, kept outside the repository.
- [ ] Verify production signatures, SHA-256, release notes and distribution licenses before tagging 1.0.

Debug-key-signed Android APK/AAB and unsigned Windows installer are testing outputs,
not public production releases. Generated or decompiled code is not guaranteed
original or buildable. No secret values belong in GitHub or analysis prompts.
