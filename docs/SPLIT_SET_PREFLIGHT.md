# Phase 35

Tools → Split APK Set Preflight compares up to 32 local APK manifests (aggregate 1 GiB), checks one observed base, package/version including versionCodeMajor, distinct split names and duplicate SHA-256. Manifest parser is bounded evidence, not a full XML validator. No dependency graph, signature verification, installability, merge, Android signing or single-APK conversion. External Apktool and owner signing workflows remain separate.
