# Phase 29

Large Binary Viewer uses regular local files up to 1 GiB, 256-byte pages, streaming SHA-256, 64 MiB search windows with boundary lookahead, and 1,000 matches per window. Continuation preserves overlapping matches. Size/mtime checked before and after operations (not a transactional filesystem snapshot). No large-file PE/ELF table decoding or editing. File-picker staging can still consume disk space; full device stress testing and security audit pending.
