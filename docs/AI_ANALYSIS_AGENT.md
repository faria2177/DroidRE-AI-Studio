# Review-gated AI research agent

AI Studio: select a provider, model and session key if needed, then choose AI Analysis Agent.
On Windows choose an authorized local source folder. Android requires an active recovered folder.
Prepare and review the plan request (question only), approve sending to the selected provider,
or choose manual search terms. Model plans are parsed as strict JSON with 1–3 literal queries;
nothing is executed. Review/edit the plan and run bounded local lexical searches, up to 3 passes
using existing ProjectContextSearch limits. Gather up to 8 distinct snippets per query/24 total.
Select up to 12 excerpts, inspect the complete report prompt and separately approve sending.
Only the selected provider is used; no automatic fallback. No code writes, command execution,
or background process. The local search can stop between bounded passes. Leaving the screen
closes the HTTP client; a sent request cannot be unsent.

The report is parsed as bounded JSON with up to 8 findings and unknowns. Each finding must cite
one or more IDs from the explicitly reviewed evidence set. Validation checks identifiers, not
semantic truth or whether a cited snippet proves the claim. The user can expand original
excerpts and copy a text report with source references. Context is held in session memory only;
no persistent agent transcript, autonomous iterative actions, or automatic file export.
Coverage is always partial. Live model/provider and device UI tests remain pending.
