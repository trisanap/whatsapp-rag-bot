# Flowise Chatflow Export

Place your exported Flowise chatflow JSON file here as `chatflow-export.json`.

## How to export from Flowise

1. Open Flowise → Chatflows
2. Click the three-dot menu on your chatflow → **Export**
3. Save the file here as `chatflow-export.json`

## Before committing to GitHub

Make sure to remove API keys from the exported JSON before publishing.
Open the file and search for any of these fields and clear their values:

- `"groqApiKey"`
- `"apiKey"`
- `"credential"`

Or export a separate clean copy without credentials selected.

## Recommended Flowise RAG pipeline nodes

```
Text File Loader
    └─► Recursive Character Text Splitter (size: 1500, overlap: 200)
            └─► Qdrant (upsert)
                    └─► Ollama Embeddings (bge-m3:latest, http://HOST_IP:11434)

Qdrant (retriever, same collection)
    └─► Conversational Retrieval QA Chain
            ├─► ChatGroq (llama-3.1-8b-instant, temp: 0.1)
            └─► BufferMemory (sessionId from WhatsApp sender JID)
```

The BufferMemory node keyed on `sessionId` gives each WhatsApp contact
their own conversation history, so the bot remembers context within a session.
