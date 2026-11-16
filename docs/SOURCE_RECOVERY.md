# On-device source recovery — milestone 1

This feature is available from **Tools → Export Source Preview ZIP** after
opening a local APK. It runs in a Dart isolate and does **not** contact AI
providers or upload an APK.

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
