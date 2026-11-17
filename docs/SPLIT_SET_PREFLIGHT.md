# Phase 35

Tools → Split APK Set Preflight compares up to 32 local APK manifests (aggregate 1 GiB), checks one observed base, package/version including versionCodeMajor, distinct split names and duplicate SHA-256. Manifest parser is bounded evidence, not a full XML validator. No dependency graph, signature verification, installability, merge, Android signing or single-APK conversion. External Apktool and owner signing workflows remain separate.

Optional Windows verification uses explicitly trusted JDK and Android SDK build-tools/lib/apksigner.jar directly with fixed verify arguments. Each APK must verify successfully and report a complete current SHA-256 signer set; sets are compared without ordering dependence. No APK is modified. Signer equality is not publisher trust, lineage validation, dependency resolution or installability. Synthetic output parser test; actual Windows SDK invocation remains untested.
