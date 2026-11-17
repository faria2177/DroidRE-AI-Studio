# Local semantic retrieval (Windows)

Install trusted local Ollama; pull all-minilm or nomic-embed-text first.
Configure the server to disable cloud features and only use trusted local models.
AI Studio → Local semantic code search (Ollama) → choose source folder →
model → question → authorize local embeddings → search.

Fixed http://127.0.0.1:11434/api/embed, no redirects, proxies, remote
embedding endpoints or automatic fallback. A local server itself is not
sandboxed or verified offline. Consent covers sampled code and question.
Separate review and consent are required for chat-provider transmission.

Up to 32 source files, 64 chunks, 4 chunks per file, 12 lines and 600
characters each. Up to four inputs/request, 90-second per-request deadline,
2,048 dimensions, 1 MiB response cap. Cosine rank up to 24 candidates,
choose 12. Partial sampling only; no persistent vector database or agent.
Code may contain secrets. Cancel stops further client requests.
Synthetic tests cover chunk bounds, mock ranking, validation and cancellation.
Real Ollama integration and latency measurements pending.
API: https://docs.ollama.com/api/embed

## Optional incremental cache and hybrid ranking

Enable Keep local vectors on disk to reuse unchanged chunk SHA-256 keys under a canonical workspace, model name and installed model digest from local /api/tags. Each completed search replaces the previous sampled vector set (up to 64 entries, 4 MiB per workspace/model). Query vectors are never retained. Cache holds derived sensitive data, not source text, and is unencrypted in app-local storage; use Clear workspace/model cache to delete it. It is opt-in per dialog, not a full vector database. Fingerprint is checked before and after the cached search; this does not guarantee the server is trustworthy or prevent an intermediate model swap. No automatic cloud fallback. Hybrid score is 75% normalized cosine and 25% keyword coverage; not a probability. Cache invalidation and ranking tests use mock embeddings.
