# APK Security Review and Version Diff

Tools → APK Security Review: review declared permissions, component inventory,
archive warnings and signature evidence. The APK must still match its recorded
SHA-256. The structural signing-block reader validates classic ZIP EOCD bounds
and APK signing-block sizes/pairs (up to 16 MiB and 256 IDs). v2/v3/v3.1 IDs
and indexed JAR signature filenames are observations only; no certificate,
cryptographic signature or signer trust verification. ZIP64 is unsupported.
Use Android SDK apksigner verify --verbose --print-certs for real verification.

Tools → APK Version Diff: import both versions, select candidate project and
choose a baseline. Comparison hashes decoded regular ZIP file contents up to
8 MiB per member and 64 MiB per APK, with a 10,000 member cap. Added/removed,
size changes, verified equal, content changes and unverified same-size
members are distinguished. Permission changes require both manifest previews.
No semantic code diff, malware verdict or runtime behavior inference.
JSON exports are local. The comparison does not execute imported code.
