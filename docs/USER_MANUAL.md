# DroidRE AI Studio — 0.8.0 preview user manual

## Install

Windows 10/11 x64: download the Windows Desktop and Installer artifact from a
successful GitHub Actions run. Extract and run Setup.exe, or extract the portable
ZIP and launch droidre_ai_studio.exe. The test installer is unsigned; verify the
artifact hash and trusted source. See WINDOWS_INSTALL.md.

Android: download the successful Flutter CI and Debug APK artifact, unzip,
verify SHA256SUMS, and install the test APK through your device's installer.
Use the ABI build for ARM64 or ARMv7 test devices. Android API 26+.
Existing installs with a different signing identity might not accept updates;
back up data before any uninstall. No production signature is provided.

## Analyze projects

1. Import an authorized APK or archive. The app keeps a local copy, computes
   SHA-256 and inventories entries. On Android choose a writable document
   folder for source recovery. On Windows choose a folder in Tools.
2. Open APK Inspector: manifest, permissions, DEX, methods, resources, ELF.
   Browse supported instructions, references, call graph and pseudo-code.
3. Export bounded source preview ZIP; repeat with the next cursor for more.
   Java-like and Dalvik previews are inspection evidence, not rebuildable code.
4. Tools → Universal Project Workspace: choose recovered folder, use file tree,
   tabs, global search, declaration hints, bookmarks and navigation history.
   Windows edits are in-memory drafts; export copies outside the input tree.
   Android SAF browsing is read-only.

## Native and framework tools

ELF: choose a file-backed section or sized function. ARM64 preview is built in;
Windows requires a trusted NDK llvm-objdump.exe for additional architectures.
For Ghidra use the optional repository script and open exported text in Workspace.
Flutter AOT: inspect snapshot symbols, string/asset evidence and candidate
version hash. This does not recover original Dart objects or source.
Framework Binary Inspector: Hermes header evidence, Unity metadata strings and
NativeScript text. Split APK & Framework Member Export saves one selected
member at a time. Optional trusted external helper: tools/framework-recovery.ps1.
See module documents for exact limits.

## Windows executable and managed .NET

Universal Binary Inspector: open EXE/DLL/ELF or raw file (32 MiB). Inspect
PE headers, imports/exports, CLR evidence, hex pages and searches. Optional
copy-only binary edit. For managed .NET choose IL & C# Recovery; install
compatible trusted ILSpy CLI and select its exe. Large Binary Viewer provides
raw 256-byte pages, SHA-256 and 64 MiB search windows up to 1 GiB.

## Authorized editing and recovery

Windows APK Asset Editor exports an unsigned copy of one edited text asset.
Smali & Resource Workspace requires Java and Apktool; decode into a unique
folder, edit, rebuild unsigned. Use tools/sign-edited-apk.ps1 with your own
authorized keystore and Android SDK Build Tools for signing. JADX recovery
requires Java and a trusted separately installed JADX distribution.
Never execute recovered application code as part of inspection.

## AI Studio

Select provider/model and a session API key if required. Desktop Ollama is
optional and separately installed. Search recovered code, select snippets,
prepare an editable prompt, review sensitive information, explicitly consent
and Send. Ranked multiple search terms are lexical, not semantic embeddings.
No APK upload or automatic execution. Fallback requires separate consent.
Google sign-in needs the owner-configured OAuth registration; Windows is
not supported. See AI_PROVIDERS.md and GOOGLE_SIGN_IN_SETUP.md.

## ADB

Windows: select trusted adb.exe, authorize USB debugging on your own device,
refresh devices, choose a third-party package. Read properties, APK paths,
PID-specific log snapshot or app memory report; optional 10 snapshot refresh
stops after the current request. No root, app install, debugger or hidden
background collection. Review logs before sharing.

## Troubleshooting and safety

If a feature is unavailable, check platform, file limits, format support,
external tools and CI status. Treat malformed/unsupported outputs as partial.
External parsers are not sandboxed; use trusted tools and authorized samples
or isolated VM. See RELEASE_READINESS.md; this is a development preview.

## Owner signing preparation

For an owner-signed APK/AAB build on Windows, follow OWNER_SIGNING.md.
The normal downloaded development artifacts still use debug signing.
