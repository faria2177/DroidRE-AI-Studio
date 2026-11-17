# Phases 26–27: member export and external recovery

Tools → Split APK & Framework Member Export → select one indexed member
(up to 80 MiB). Archive SHA-256 is checked, then the selected regular ZIP
member is saved via the platform picker. The exported file has its own SHA-256.
Nested APKs can be imported individually; no split merging, bundletool
reconstruction or common-signature validation. Desktop refuses existing outputs.
Android provider controls final save; choose a new file.

For compatible Hermes versions, use separately installed hbctool in a trusted
environment. For Unity, export matching libil2cpp.so and global-metadata.dat.
Optional Windows tools/framework-recovery.ps1 invokes trusted hbctool.exe
(disasm) or Il2CppDumper.exe with explicit arguments and a new output directory.
No automatic tool download, patching, protection bypass or input execution.
Compatibility, timeout and disk output depend on these external tools;
interactive CLI may require manual intervention. Open recovered text in Workspace.
NativeScript source assets can be exported directly when present. No original JS
or C# reconstruction guarantee. Real external integration tests pending.

Existing Apktool workspace and tools/sign-edited-apk.ps1 support authorized
unsigned rebuild and SDK zipalign/apksigner sign/verify on Windows. Android
in-app signing, multi-split rebuild, release keystore provisioning and bundle
reconstruction remain pending.
References: https://github.com/bongtrop/hbctool and
https://github.com/Perfare/Il2CppDumper .
