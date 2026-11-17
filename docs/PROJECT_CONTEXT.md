# AI project context

AI Studio → Search active recovered project (Android SAF or local recovery
folder); on Windows choose a trusted JADX/local source folder. Search one
literal keyword or phrase, then select up to 12 excerpts with relative path
and line numbers. Enter a question and prepare the prompt. Review the
complete editable prompt, remove sensitive material, select provider/model,
and explicitly consent before Send. Existing fallback requires separate
consent. Search itself never contacts any network.

Bounds: 2,000 listed entities, 500 attempted text files, 64 KiB/file,
4 MiB processed text, 60 excerpts, up to five lines per excerpt, clipped
long lines. SAF uses existing bounded provider listing/preview and is
always marked partial. Unsupported encodings or unreadable files are
skipped. This is lexical retrieval, not vector embeddings, full repository
indexing, semantic code graph or an autonomous agent. AI output can be
wrong; no AI-driven file writes, shell commands, or automatic uploads.
Tests cover local text filtering, path checks, line references and drafts.
