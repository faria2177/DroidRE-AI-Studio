# On-device source recovery — milestone 1

Source recovery runs **automatically after APK import** and saves a real
Android application-owned folder. From **Tools** you can browse generated files
or export a ZIP. Processing runs offline in Dart isolates, without uploading
an APK or contacting an AI provider.

## Automatic Android folder generation

After a successful import, DroidRE automatically runs the bounded offline
analysis and writes individual files under an app-owned directory similar to:

\`/storage/emulated/0/Android/data/com.jahid.droidreai/files/DroidRE_SourceProjects/<package>_<project-id>/\`

The path is obtained from Android's app-specific external files directory at
runtime, not hardcoded. If external storage is unavailable, app support storage
is used. No all-files permission is requested. **New Android versions may hide
Android/data from third-party file managers**, so the app provides **Tools →
Browse Generated Code** to list and preview files internally. The existing
**Export Source Preview ZIP** option remains available for sharing or copying
the files outside the restricted directory. Uninstalling the app can remove
its app-specific generated files.

Folders include:

- \`source/java_like/dex_XX/com/example/Class_XXXX.java.txt\` — package-based
  Java-like pseudocode (NOT compilable Java).
- \`source/dalvik/dex_XX/com/example/Class_XXXX.dalvik.txt\` — package-based
  Dalvik reports (NOT assemblable Smali).
- \`recovered/dex_XX/classes/XXXX/\` — class/method metadata and original
  bounded inspection output.
- \`resources/raw/\`, \`resources/decoded/\`, \`REPORT.json\`, \`README.md\`.

Import is considered successful once the APK is indexed, even when source
recovery fails. In that case the UI reports the recovery error separately.
Generated folder paths and partial-result flags are persisted with the project.
The folder is never silently overwritten, preserving any user's later edits.

## Contents

- \`README.md\`: non-compilable/non-assemblable status and limitations.
- \`REPORT.json\`: input package/SHA-256, counts, exact per-class coverage,
  local source file mappings, skipped files, and partial-result warnings.
- \`recovered/dex_XX/INDEX.txt\`: per-DEX summary.
- \`recovered/dex_XX/classes/XXXX/class.txt\`: class name/flags/count.
- \`methods.txt\`: declared method names, signatures and code offsets.
- \`java_like.txt\`: **approximate Java-like pseudocode only**.
- \`dalvik.txt\`: **decoded Dalvik inspection text only**, not assemblable Smali.
- \`resources/raw/XXXX.bin\`: bounded raw XML/assets/resource bytes.
- \`resources/decoded/XXXX.xml\` or \`.txt\`: decoded preview where possible.

## Limits and security

- First 3 supported DEX files, first 80 classes, first 400 methods.
- 32 small resources (up to 256 KiB each, 4 MiB aggregate).
- DEX files above 32 MiB and output ZIP above 24 MiB are refused.
- A large/unreadable method or resource may be omitted with a warning;
  \`REPORT.json\` distinguishes partial output.
- ZIP entry names are normalized and validated to prevent traversal or
  duplicate source names. Export paths are generated locally by DroidRE.
- The original APK is not modified, run, rebuilt, signed, or transmitted.
- Export is opt-in using the operating system save dialog. The output
  contains code/strings and might be sensitive. Review before sharing.

## What is not implemented

This is **not** JADX/Apktool-equivalent source recovery. Original Java/Kotlin,
compiled Flutter Dart, original comments, exact method bodies in Smali syntax,
full resource names, Gradle project files and buildable Android Studio source
cannot be reconstructed in this milestone.

Next milestones: more complete DEX code and annotations, class/field metadata,
Smali fidelity/round-trip validation, deeper resource decoding, and a project
scaffold with explicit buildability tests. Those are planned, not complete.
