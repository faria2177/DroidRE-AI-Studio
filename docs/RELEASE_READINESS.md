# Phase 42 — 0.9.1 development preview readiness

Do not label this version 1.0 production-ready. Phases are development workstreams,
not a percentage estimate of verified functionality.

| Phase | Implemented scope | Remaining gate |
| --- | --- | --- |
| 22 | Declaration hints, app-local bookmarks/history | Semantic index, version history, device UI |
| 23 | Ranked local evidence, opt-in vector cache, reviewed multi-step agent | Live Ollama/provider validation, larger index, semantic citation verification |
| 24 | Manual and in-app headless Ghidra function/call/pseudocode export | Actual Ghidra/JDK validation, complete native CFG |
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

## Owner signing preparation

An explicit owner signing Gradle configuration and local verified-artifact
helper now exist (OWNER_SIGNING.md). No actual owner credential or signed
device build has been provided or verified; the gate stays open.

## Phases 31–42 status (bounded implementation)

| Phase | Delivered in preview | Remaining |
| --- | --- | --- |
| 31 | Compare candidate Dart snapshot hash with trusted reference | Version catalog, exact VM layout, object pool and Dart class/function reconstruction |
| 32 | HBC 76 function/header/operand preview and simple register pseudocode | Other HBC versions, overflow headers, full JS CFG and real fixtures |
| 33 | Literal index and classic IL2CPP 27/29 type/method metadata mapping | Actual Unity fixtures, native address registration and source/body recovery |
| 34 | Headless Ghidra block edges, DOT and pinned Linux synthetic smoke | Windows tool/runtime validation, interactive full CFG |
| 35 | Split APK manifest identity and optional SDK current signer-set verification | Actual SDK runtime check, dependencies, merge/rebuild, in-app signing |
| 36 | Bounded foreground live Logcat | Physical device tests, debugger and broader runtime inspection |
| 37 | Original/draft line diff and lexical declaration suggestions | Semantic language server, persistent code versions |
| 38 | Reviewed AI report export, refine loop, opt-in saved research plan and excerpt freshness check | Semantic report verification / live provider tests |
| 39 | Common tool path detection, version commands and install links | Runtime compatibility matrix, automatic configuration, actual local tool checks |
| 40 | Pruned bounded directory traversal | Large project indexing, RAM/latency measurements and benchmark |
| 41 | Manifest/member parser hardening and deterministic malformed-header tests | Full security audit, broader fuzzing and real device QA |
| 42 | 0.9.0 preview version, documentation and same-commit build workflows | Verified production credentials, full integration/device validation and signed release |

No production tag has been created. The Android workflow remains test-signed and Windows setup remains unsigned. Actual owner signing requires local keys and verification using the existing owner signing helper. The pinned Ghidra synthetic integration workflow is independent of Android and Flutter packaging.

0.9.1 additionally addresses lost AI setup across navigation and inspector drafts, model/authentication diagnostics, native Gemini and a free-router choice. Mock tests verify request/response and widget behavior. A real account with valid provider credentials is still needed to verify live access. See AI_STUDIO_TROUBLESHOOTING.md.
