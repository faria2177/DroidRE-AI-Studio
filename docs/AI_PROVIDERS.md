# AI providers — MVP and roadmap

## Working request adapters

The AI Studio UI supports explicit chat-completion calls with user API keys:

- OpenRouter
- OpenAI
- DeepSeek
- Groq

You must enter a model ID that the selected provider actually offers to your
account. Model availability and pricing change. **No model is guaranteed free**.
Keys are kept in memory only; leaving the screen clears them. Neither APK files
nor decompiled text are automatically sent.

## Roadmap

Google Gemini, Anthropic Claude, xAI Grok, Qwen, Z.ai/GLM, Mistral, Hugging Face,
Together, Cerebras, local Ollama and other official APIs will be added through
individual verified adapters. Later milestones include live model discovery,
cost budgets, 429-aware fallback, opt-in project RAG and on-device models.

Paid provider access always requires appropriate user credentials or an
authenticated metered backend. No key scraping or quota circumvention.
