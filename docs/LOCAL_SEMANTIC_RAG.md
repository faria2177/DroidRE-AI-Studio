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
