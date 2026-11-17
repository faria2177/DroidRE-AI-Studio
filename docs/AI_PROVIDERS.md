# AI providers

AI Studio offers OpenRouter, OpenAI, DeepSeek, Groq, Google Gemini (OpenAI
compatibility endpoint), Anthropic Claude (Messages API), xAI Grok (legacy
chat-completions endpoint), Mistral, and Ollama loopback on desktop.
Enter a current model ID available to your account. No model is guaranteed
free. Keys are session-only; no whole APK is sent. Cloud requests require
explicit prompt review consent. Changing the primary provider clears its key.

## Optional fallback

Select a different fallback provider, its own model/key, and explicitly
consent to sharing the same prompt. One attempt is made only on HTTP 429,
502, 503, 504 or 529. No fallback on auth errors, timeouts, malformed
responses or redirects. A fallback can incur separate charges. The output
identifies the provider and trigger. Prompts are capped at 40,000 characters
and successful responses at 2 MiB.

Ollama requires a running local server at localhost:11434 and downloaded
model on the desktop device. The Android UI hides this option; no cleartext
network policy relaxation or model bundling is included. Local inference is
not guaranteed just by choosing a model name (Ollama can route cloud models).
Use a verified locally downloaded model for offline use.

Official documentation: https://ai.google.dev/gemini-api/docs/openai ,
https://platform.claude.com/docs/en/api/messages/create ,
https://docs.x.ai/developers/rest-api-reference/inference/chat-completions ,
https://docs.mistral.ai/api/endpoint/chat ,
https://docs.ollama.com/openai .

Mock HTTP tests verify adapter request/response shape, not live provider
availability. More providers, multi-step agents,
cost budgets, project RAG and Android local inference remain future work.

## Model catalog

Fetch available model IDs explicitly for the primary or fallback provider.
Only a GET request with that provider's session credential is sent; no prompt.
First response only, bounded to 2 MiB and 1,000 IDs; manual entry remains
available. Model listings do not guarantee chat compatibility, access or free
use. Catalog requests never trigger fallback.
