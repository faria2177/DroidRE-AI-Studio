# DroidRE AI Studio

An **Android-first Flutter project** for offline APK inspection and optional AI code explanations.

**Current version:** 0.4.0 — read-only Dalvik opcode/operand disassembly, Android binary XML viewer and opt-in AI code explanations; not a full JADX or Apktool replacement.

## What works today

- Original DroidRE cyan/violet logo, Android adaptive/legacy launcher icons, branded startup and in-app header.
- Modern Material 3 home, projects, analysis, tools and AI screens.
- Android file picker import for APK/ZIP, and basic APKS/XAPK/APKM/AAB container listing.
- Read-only local archive enumeration, file count, SHA-256, DEX/native `.so` inventory, and limited framework indicators.
- On-demand DEX class/method-name browser (DEX 035–040) with search; ELF32/ELF64 header inspection for native libraries.
- Tap supported DEX methods to view prototype signatures, access flags and a **non-assemblable Smali-style code-unit preview** (with limited opcode hints).
- Browse `res/` and `assets/` paths, inspect compiled `resources.arsc` package headers, preview small text/images and binary hex headers locally.
- On-demand Dalvik instruction parsing for standard DEX 035–040 opcodes and formats, with branch offsets, register operands and payload boundaries; unsupported instructions are reported honestly.
- Decode compiled Android XML resource element/attribute hierarchy (up to 2 MiB per XML); resource references are shown as IDs until full `resources.arsc` value resolution is available.
- Tap **Explain with AI** on a selected DEX method or decoded XML to prefill the AI Studio prompt. Text is only sent after explicit consent and Send; no APK upload.
- Decode common fields from Android binary XML or plain XML manifests, including package/version/SDK/permission/component names.
- Projects are stored in app-private local storage and can be reopened.
- Opt-in AI chat with your own OpenRouter, OpenAI, DeepSeek or Groq API key; only text that you explicitly enter leaves the device.
- Google account button and OAuth integration path. The button requires owner-provided OAuth configuration.
- CI, unit tests and Android debug APK workflow.

See [Feature status](docs/FEATURE_STATUS.md) for precise limitations.

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
