# Windows Smali and resource workspace

Only for APKs you own or are authorized to modify. Install Java and obtain
an official, trusted and up-to-date Apktool JAR from https://apktool.org/.
DroidRE does not bundle Java, Apktool, or Android SDK build tools.

Import one APK → Tools → Smali & Resource Workspace. Explicitly confirm
tool trust, select installed java.exe, the trusted jar, and a destination.
Decode creates a fresh subfolder with its own framework cache. Original
imported APK is SHA-256 checked and never rewritten by this workflow.
The editor opens existing UTF-8 .smali, res/*.xml and AndroidManifest.xml
inside the decoded tree, max 512 KiB per file. Save edits, then Rebuild
unsigned APK; each build uses a new output subfolder. Apktool does the
assembly and resource compilation, not DroidRE's read-only Dalvik preview.
Errors and the last 32,000 log characters are displayed. Java heap capped
at 1536 MiB, process wait up to ten minutes. No shell interpolation.

Apktool itself is an external executable and not sandboxed. Only analyze
trusted input or use an isolated VM; malicious packages may exploit parser
bugs. Do not select a jar supplied by the APK. Workspace files and outputs
remain on disk; remove them manually if desired. Requires a compatible
Apktool version and frameworks. Split APKs, OEM framework dependencies,
signing and installation are not automated. Use the authorized SDK signing
helper in docs/APK_EDITING.md. A successful build does not prove the APK
will run. Android version retains preview and asset repacking only.

CI tests cover argument construction and workspace path/text boundaries;
real Apktool/Java integration needs a local round-trip build test.
