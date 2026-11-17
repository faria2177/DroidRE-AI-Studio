# Phase 22

Workspace menu: declaration hints, session line bookmarks, last 100 navigation locations. Scan 250 files / 2 MiB / 3000 records. Regex hints only, not semantic resolution; history and bookmarks are not persisted.

## Persistent navigation

Bookmarks and the last 100 visit locations are saved per workspace in app-local storage, keyed by a SHA-256 of its canonical directory or SAF URI. Only relative paths and line numbers are stored; no source content. Use the menu to clear saved navigation. Locations may be stale after external file edits/deletion. On storage failure the current session remains usable. No persistent draft/code version history.
