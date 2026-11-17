# Flutter application structure evidence

ELF Explorer → libapp.so → Analyze Flutter AOT snapshots → Strings & assets.
The analyzer scans printable ASCII runs (5+ bytes) in known, sized snapshot
data regions. If no sized data region is available it scans read-only allocated
non-executable PROGBITS sections, explicitly marking fallback. Up to 2 MiB
of bytes and 1,000 string records, 256 characters per displayed run. Offsets
refer to the ELF file, not APK ZIP offsets or Dart object addresses. URI and
path classifications are heuristics. Non-ASCII and Dart-specific encodings
are not decoded. No object-pool or Dart VM deserialization is performed.

The inventory lists up to 5,000 regular paths below assets/flutter_assets/,
including manifest filenames, package folder hints and asset sizes. It does
not parse AssetManifest.bin, infer missing dependencies, or recover Dart
source. Search, copy and export local JSON. Review sensitive strings before
sharing. No network access or uploaded binary. Tests cover scope, limits,
offsets and asset inventory; device-level and real APK validation pending.
