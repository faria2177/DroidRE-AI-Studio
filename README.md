# DroidRE AI Studio

An **Android-first Flutter project** for offline APK inspection and optional AI code explanations.

**Current version:** 0.9.1 development preview — local Android/Windows reverse-engineering tools and optional AI. Version-specific evidence, external tools and bounded recovery; not a complete original-source recovery product. See [Release readiness](docs/RELEASE_READINESS.md).

## What works today

- Original DroidRE cyan/violet logo, Android adaptive/legacy launcher icons, branded startup and in-app header.
- Modern Material 3 home, projects, analysis, tools and AI screens.
- Android file picker import for APK/ZIP, and basic APKS/XAPK/APKM/AAB container listing.
- Read-only local archive enumeration, file count, SHA-256, DEX/native `.so` inventory, and limited framework indicators.
- On-demand DEX class/method-name browser (DEX 035–040) with search; ELF32/ELF64 header inspection for native libraries.
- Tap supported DEX methods to view prototype signatures, access flags and a **non-assemblable Smali-style code-unit preview** (with limited opcode hints).
- Browse `res/` and `assets/` paths, inspect compiled `resources.arsc` package headers, preview small text/images and binary hex headers locally.
- On-demand Dalvik instruction parsing for standard DEX 035–040 opcodes and formats, with branch offsets, register operands and payload boundaries; unsupported instructions are reported honestly.
- Resolve DEX method, field, string, type and prototype references to human-readable descriptors when available. Tap outgoing method references to navigate to indexed declarations, or **Find callers** to scan other indexed methods in the same DEX (bounded, best effort).
- **Call graph** scans up to 24 DEX entries by method signature, finding direct callers/callees and two-hop relationships across `classes.dex`/`classes2.dex` etc., with limits and incomplete-scan warnings.
- **Normal-flow control graph:** basic blocks, jump/conditional/switch successors, backward edges and normal-flow reachability in the Dalvik method view and source preview; exception flow is excluded.
- **View Java-like pseudocode** renders conditional operators, register arithmetic, field receivers, arrays and locally linked invoke results with Dalvik offsets; it does not recover original Java source.
- Decode compiled Android XML resource element/attribute hierarchy (up to 2 MiB per XML); resource references are shown as IDs until full `resources.arsc` value resolution is available.
- Tap **Explain with AI** on a selected DEX method or decoded XML to prefill the AI Studio prompt. Text is only sent after explicit consent and Send; no APK upload.
- AI method prompts include resolved references and request evidence by instruction offset, behavior, risks, uncertainties and next targets; the user can review and edit everything before sending.
- Decode common fields from Android binary XML or plain XML manifests, including package/version/SDK/permission/component names.
- Projects are stored in app-private local storage and can be reopened.
- Opt-in AI chat with eight cloud providers and desktop Ollama; explicit bounded model discovery and one optional fallback with separate consent.
- Google account Settings accepts a Web OAuth client ID directly on the device and supports interactive sign-in/session restore **when** a matching Google Cloud Android OAuth registration and signing certificate fingerprint are configured. No Gmail inbox permission is requested.
- Google account button and OAuth integration path. The button requires owner-provided OAuth configuration.
- CI, unit tests and Android debug APK workflow.

See [Feature status](docs/FEATURE_STATUS.md) for precise limitations.

## APK asset editing

Tools → APK Asset Editor supports one existing UTF-8 text asset per export.
The imported source is hash-checked and unchanged. Output is an unsigned
ZIP-repacked copy, with retained payload hashes verified. The Windows SDK
signing helper is documented in [APK editing](docs/APK_EDITING.md).
On-device signing and full compiled resource rebuilding remain planned.

## Flutter AOT snapshot evidence

Open ELF Explorer, select libapp.so, then Analyze Flutter AOT snapshots.
Supports legacy VM/isolate and consolidated Dart snapshot symbol names,
validates section/address mapping, and displays raw 64-byte header samples.
Copy a JSON report locally. This is not Dart object-pool decoding, version
identification, or Dart source decompilation. Stripped symbols remain unknown.

## Native ARM64 preview

In the ELF explorer, tap an executable section row or the code icon beside
an eligible sized function symbol. The paged read-only linear sweep shows
virtual address, raw word, known mnemonic and operands. Direct branch targets
use instruction-relative addresses. Unsupported words stay `.word`.
Only little-endian AArch64 executable/shared ELF files and file-backed
executable PROGBITS ranges are accepted. No native execution or decompilation.

## On-device source project folders

When an APK is imported, DroidRE detects framework indicators, inspects
supported DEX and resources offline, and asks the user to choose a public
folder using Android's **system document-tree picker**. The application then
creates a new \`DroidRE_<package>_<id>\` directory under the chosen location,
such as \`Documents/\`, outside \`Android/data\`. The destination is remembered
for later imports. The app provides **Tools → Choose File Manager Folder**,
**Generate Code in Selected Folder**, **Browse Generated Code** and
**Export Source Preview ZIP**.

Output includes package-organized Java-like pseudocode and Dalvik inspection
text, decoded/raw resource previews, technology-specific analysis for
Native Android, Flutter, React Native, Unity or NativeScript, and structured DEX class metadata (superclasses, interfaces, source-file
hints and fields in \`CLASS_METADATA.json\`), bounded try/catch and
code-reference details in \`method_semantics.json\`, and annotation type
inventories and bounded encoded values in \`ANNOTATIONS_INDEX.json\`.
Where debug information exists, `method_debug_info.json` also contains
source line/parameter/local-variable names; stripped or invalid debug data
is not guessed. Coverage warnings remain in \`REPORT.json\`. It is **not** original source, compilable Java,
assemblable Smali or a rebuildable Android Studio/Flutter project.
If the user cancels folder selection, importing the APK still succeeds.
The source ZIP also includes compiled resource value/bag metadata and typed
XML reference name hints in `resources/RESOURCE_TABLE.json` and
`resources/XML_REFERENCES.json`, without rewriting raw IDs.
For large APKs, Tools → Export Source Preview ZIP supports a zero-based
DEX:class:method cursor; the next cursor is filled after a successful save.
See [Source Recovery](docs/SOURCE_RECOVERY.md) for limits, permitted folder
locations, and privacy details.

## Android development build

The latest source-recovery changes are packaged as development version **0.9.1+11**.
GitHub Actions **Flutter CI and Debug APK** runs `flutter analyze`, `flutter test`,
and then builds an Android debug APK from `main`. The artifact is signed
with the development debug key; it is for testing, not Play Store release.
See [workflow](.github/workflows/flutter-ci.yml).

## Run locally

Flutter SDK **3.47.4** with a compatible Android SDK/JDK is the initial target.
If you are using a different Flutter version, align AGP/Gradle versions with its toolchain.

```bash
git clone https://github.com/faria2177/DroidRE-AI-Studio.git
cd DroidRE-AI-Studio
flutter create . --platforms=android --org com.jahid --project-name droidre_ai_studio
flutter pub get
flutter analyze
flutter test
flutter run
```

> The first `flutter create` fills in generated Flutter platform files (including
> Gradle launcher assets) that are not checked in for this initial milestone.
> The project is also bootstrapped in GitHub Actions.

The Android application ID is `com.jahid.droidreai`.

## GitHub APK builds

1. Open **Actions → Flutter CI and Debug APK**.
2. Select **Run workflow**, or push to `main`.
3. Wait for tests and the debug build.
4. Download the **droidre-debug-apk** artifact and install the APK on Android.

The manual **Android ABI APKs (testing only)** workflow produces
`armeabi-v7a` and `arm64-v8a` test builds. These are **debug-key signed**,
not production releases.

For setup: [BUILD.md](docs/BUILD.md) · [Google Sign-In](docs/GOOGLE_SIGN_IN_SETUP.md)

## Architecture

Flutter drives UI, projects, local binary archive indexing and opt-in AI requests.
The current Dart readers inspect DEX indices, bounded Dalvik instruction sequences,
ELF headers, Android compiled XML and top-level resource tables. A future Kotlin/native
analyzer may handle full Smali/ELF disassembly. Optional heavyweight
desktop worker integrations are documented as future features.

The analyzer never executes imported binary code and never sends an APK to an AI provider.

## Responsible use

Use this application only on software that you own or have permission to inspect,
modify or assess. No license bypass, credential extraction, hidden monitoring
or unauthorized intrusion functions are included.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Feature status and limitations](docs/FEATURE_STATUS.md)
- [Android / GitHub build](docs/BUILD.md)
- [Google Sign-In setup](docs/GOOGLE_SIGN_IN_SETUP.md)
- [AI provider setup](docs/AI_PROVIDERS.md)

### Multi-AI routing

Eight cloud providers plus desktop Ollama loopback; explicit consent for a single fallback. See [API providers](docs/AI_PROVIDERS.md) for limits.

## Windows Desktop

Windows x64 build and one-click per-user installer workflow: see [Windows install guide](docs/WINDOWS_INSTALL.md). Portable ZIP and installer are CI artifacts; Google login on Windows remains unsupported. Desktop output folder selection and Ctrl+O import are available.

## Windows Smali & Resource Workspace

Tools → Smali & Resource Workspace: decode, edit existing Smali/XML and rebuild an unsigned APK using separately installed Java and trusted Apktool. See [workspace guide](docs/APKTOOL_WORKSPACE.md). External tooling is not sandboxed or included in the installer.

## Expanded development preview (phases 12–30)

- [Native LLVM and XREF](docs/NATIVE_EXTENDED_ANALYSIS.md) · [Flutter structure](docs/FLUTTER_STRUCTURE.md) · [JADX](docs/JADX_RECOVERY.md)
- [AI context](docs/PROJECT_CONTEXT.md) · [ADB](docs/ADB_INSPECTION.md) · [Framework binaries](docs/FRAMEWORK_BINARY.md)
- [Universal binary](docs/UNIVERSAL_BINARY.md) · [PE directories](docs/PE_DIRECTORY_ANALYSIS.md) · [.NET and ILSpy](docs/DOTNET_RECOVERY.md)
- [Project workspace](docs/PROJECT_WORKSPACE.md) · [Project intelligence](docs/PROJECT_INTELLIGENCE.md) · [AI ranked retrieval](docs/AI_PROJECT_INTELLIGENCE.md)
- [Optional Ghidra](docs/GHIDRA_RECOVERY.md) · [Dart hash evidence](docs/DART_VERSION_EVIDENCE.md) · [Framework/split export](docs/FRAMEWORK_AND_SPLIT_EXPORT.md)
- [ADB runtime monitor](docs/ADB_RUNTIME_MONITOR.md) · [Large binary viewer](docs/LARGE_BINARY.md)
- [User manual](docs/USER_MANUAL.md) · [Release gates and remaining work](docs/RELEASE_READINESS.md)

## Phases 31–42 preview

[Framework version mapping](docs/FRAMEWORK_VERSION_MAPPING.md) · [Hermes 76](docs/HERMES76.md) · [Unity metadata definitions](docs/IL2CPP_DEFINITION_MAPPING.md) · [Ghidra headless / CFG](docs/GHIDRA_HEADLESS.md) · [Split set preflight](docs/SPLIT_SET_PREFLIGHT.md) · [Live Logcat, draft diff and reviewed reports](docs/PHASES_36_38.md) · [External tool manager](docs/EXTERNAL_TOOL_MANAGER.md) · [Performance and security hardening](docs/PERFORMANCE_SECURITY_HARDENING.md).

The Ghidra synthetic fixture workflow tests the pinned official release with a compiled sample, not a Windows device install. Hermes 76 opcode data is distributed under the MIT license in third_party/licenses/hbctool-MIT.txt. Review the remaining gates before production signing or public release.

## AI Studio troubleshooting (0.9.1)

[AI Studio provider setup, connection tests and session handling](docs/AI_STUDIO_TROUBLESHOOTING.md). API key and model access are required for real cloud calls. No credentials are bundled.
