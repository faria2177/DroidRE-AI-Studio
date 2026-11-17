# Phases 40–41 — targeted hardening

Workspace and lexical search share a depth/entry/file-capped, non-symlink
traversal that prunes generated/hidden folders before descending. This prevents
generated-file trees from dominating the eligible-source budget. Real 8 GiB
machine profiling and larger indexing/parallelism remain pending.

Manifest reader caps input, respects declared document length, constrains
attribute counts, rejects duplicate manifest markers, isolates identity fields,
validates string table offsets/terminators, reuses duplicated string offsets
and limits cumulative decode work. It remains a partial parser, not a full
XML/AXML validator. Package member reader rejects ambiguous/unsafe paths,
limits archive size and requested member size. Archive decompressor allocation
is not fully sandboxed; hostile ZIP bomb testing and review remain necessary.
Deterministic malformed-header tests and traversal budget regression added.
No claim of completed formal audit, exhaustive fuzzing or real-device QA.
