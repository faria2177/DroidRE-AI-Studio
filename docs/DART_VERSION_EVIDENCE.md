# Phase 25 — Dart snapshot version evidence

Existing Flutter AOT JSON export now includes a candidate classic snapshot
version hash for sufficiently sized data regions with matching magic, plausible
length and 32 ASCII hexadecimal bytes at offset 20. Raw kind is deliberately
not mapped across VM versions. Compare hash against trusted SDK build metadata;
no automatic SDK mapping, object pool/type/function decoder or original source.
Source layout references:
https://dart.googlesource.com/sdk/+/9a9affb930e4d53410f645769da22208743af513/runtime/vm/snapshot.h
https://dart.googlesource.com/sdk/+/095171e937b71acad49bb9793115f5a83ab6fff7/runtime/vm/app_snapshot.cc
