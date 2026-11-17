# Universal Project Workspace

Tools → Universal Project Workspace. Opens the active recovered folder or,
on Windows, select a local JADX, Apktool, ILSpy or other authorized source
folder. Android uses existing SAF recovery access and is read-only.

Expandable tree, filename filter, eight simultaneously open tabs,
lightweight lexical keyword/string/comment coloring, exact in-tab search,
and disk-based global search via ProjectContextSearch. Global results have
relative path and excerpt line; selecting a result places the caret at the
start of its excerpt (not guaranteed scroll positioning). Global search
uses the workspace text extension allowlist, including C# and project files,
not unsaved drafts.

Windows edits remain in memory; export one edited copy to a NEW file
outside the source tree. No original writes, autosave, build, execution,
or network access. Closing edited drafts requires discard confirmation.
Maximum 4,000 visited entities, 1,500 listed text paths, 64 KiB per opened
or exported file. SAF listing is explicitly partial. Highlighting is
heuristic, not a full syntax parser, no language server, debugger or AST.
Tests cover listing, path and text bounds. UI/device validation pending.
