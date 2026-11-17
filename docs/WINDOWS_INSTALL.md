# Windows x64 installation

Windows 10/11 x64. From the successful Windows Desktop and Installer
GitHub Actions run, download the droidre-windows-x64 artifact. Extract
the outer artifact ZIP. It contains:

- DroidRE-AI-Studio-x64-Setup.exe: per-user setup, Start menu shortcut,
  optional desktop shortcut and uninstall support.
- DroidRE-AI-Studio-x64-Portable.zip: extract the complete archive to
  a folder and run droidre_ai_studio.exe. Do not move the EXE alone.
- SHA256SUMS.txt: verify downloads with Get-FileHash -Algorithm SHA256.

Artifacts are unsigned development builds. Check the hash and repository
before running. App-local VC runtime DLLs are included; no Flutter SDK
is required on the target PC. No Authenticode certificate is supplied.

Local projects do not require an account. Google sign-in is not
implemented on Windows. Ollama requires a separately installed local
server/model. Choose a recovery output folder in Tools; the selection
lasts until the process closes. Generated files do not replace existing
folders. Ctrl+O opens the APK picker. Windows and Android use the same
Dart analysis modules and their documented limits.

## Build on a development PC

Install Flutter 3.47.4, Visual Studio 2022 with Desktop development with
C++ (including Windows SDK and CMake), and Inno Setup 6. Run from the
repository root:

    flutter create . --platforms=windows --org com.jahid --project-name droidre_ai_studio
    flutter pub get
    flutter analyze
    flutter test
    flutter build windows --release
    .\tools\package-windows.ps1

Output: dist directory. The packaging script requires the Visual Studio
redistributable CRT files and Inno Setup compiler. CI tests do not
replace testing installation on a real Windows system.
