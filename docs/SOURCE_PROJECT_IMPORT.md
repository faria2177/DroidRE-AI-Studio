# Android Code Studio / source project workflow (0.9.3 preview)

Home → Import APK or source project → Android Code Studio / Flutter project ZIP
or source folder. On Android the folder option uses a read-only Storage Access
Framework grant and copies into app-private storage. Choose the actual project
folder (the folder containing settings.gradle/build.gradle or pubspec.yaml),
not a shared-storage root or Android/data. Private folders of another app may
not be accessible through Android's picker; export the project to a ZIP first.

The imported copy is registered in Projects; select Analyze → Open source
editor / export ZIP. On a phone choose Files then tap a text file to open
Editor. Save writes to the imported copy only; export the ZIP using the archive
icon in the toolbar. The ZIP preserves the included paths and binary assets and
includes saved edits plus currently open drafts. Extract it to a new folder in
Android Code Studio or Android Studio and restore SDK paths/signing settings.
Choose a new output filename. Original project files are never edited by the
workspace. The application does not guarantee a buildable project or run Gradle.

Supported: Android Java/Kotlin Gradle projects, Flutter source projects, and
Android source projects with recognizable manifest and Java/Kotlin source.
Limits: 128 MiB source ZIP/copy, 24 MiB per file, 8,000 files, 16,000 entries,
32 path segments, 512-character relative paths. Text editor: 64 KiB per file
and eight open tabs, bounded file tree/search. Export is in-memory and may
need substantial RAM for large projects. Directory structure is preserved;
if the ZIP has a top-level wrapper folder, it remains. Generated build/caches,
common keystore/private-key filenames and local.properties are excluded.
This is not comprehensive secret detection or ZIP-bomb sandboxing; use trusted
projects and review code before sending it to an AI provider.

Analyze source project with AI and AI Gradle build troubleshooting prepare
questions for AI Studio. A pasted actual build error is useful for diagnosis.
AI uses bounded active-project excerpts, privileges build configuration in
ranking, and requires explicit review/consent. AI does not automatically
apply generated patches. Save edits in the editor manually. Project summary
counts and hash are the original import snapshot; analysis reads saved files.
No APK compilation, device installation or real Android Code Studio round-trip
is verified by these unit tests. Android folder picker needs physical-device QA.
