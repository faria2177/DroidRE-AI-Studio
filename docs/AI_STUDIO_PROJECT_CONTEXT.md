# Active project context and follow-up chat

AI Studio previously sent only the text in the prompt field. Generated
files were not automatically attached, and each call was stateless.
Use Prepare active project analysis to create a locally selected, editable
brief with APK metadata and up to 12 excerpts (48 file attempts, 2 MiB source
read budget, 32,000 character prompt target). Supports Android recovered SAF
or regular local folders. Metadata-only if no readable excerpts exist.
Review before consent/Send. No whole APK upload or automatic transmission.

Ask follow-up starts a new question with the last three successful raw
question/answer turns available in memory. History included by default, with
an exact combined-prompt confirmation before sending; disable via switch.
Prior answers are not evidence. Context is clipped to 40,000 characters.
New chat, imported inspector draft, active project or recovery destination
changes clear prior context. No keys or conversation stored on disk.
Mock/fixture tests verify evidence and memory; actual provider/device test pending.

The active-project switch is enabled by default: ordinary questions up to 2,000 characters automatically prepare a bounded brief before the combined-prompt review. Nothing is transmitted until approved. Disable it for standalone questions or paste a pre-reviewed evidence draft. History is bounded by remaining request capacity.
