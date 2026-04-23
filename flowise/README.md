# Flowise Chatflows

Two chatflow files are included. Import both into Flowise before starting.

| File | Purpose |
|---|---|
| `RAG_Ingest_Chatflow.json` | One-time step — loads your knowledge base file, chunks it, and indexes it into Qdrant |
| `Chatbot_Chatflow.json` | The live bot — retrieves from Qdrant and answers user questions via the LLM |

## How to import

1. Open Flowise at `http://YOUR_HOST_IP:3000`
2. Go to **Chatflows** → click the **Import** button
3. Select the JSON file
4. Repeat for the second file

## After importing — update these values

Both chatflows have placeholder URLs that must point to your actual host:

| Node | Field | Replace with |
|---|---|---|
| Qdrant | Server URL | `http://YOUR_HOST_IP:6333` |
| Ollama Embeddings | Base URL | `http://YOUR_HOST_IP:11434` |
| ChatGroq | Credential | Your Groq API key (add via Flowise → Credentials) |

> If you're using a local Ollama LLM instead of Groq, replace the **ChatGroq** node
> with a **ChatOllama** node pointing to `http://YOUR_HOST_IP:11434`.

## Indexing your knowledge base

1. Open **RAG Ingest Chatflow**
2. Click the **Text File** node → upload your knowledge base file
3. Click **Upsert** (top right) — this chunks and indexes the file into Qdrant
4. You only need to re-run this when your knowledge base changes

## Customizing the system prompt

Open **Chatbot Chatflow** → click the **Conversational Retrieval QA Chain** node →
edit the **Response Prompt** field. The included prompt is a generic template with
`[BOT_NAME]`, `[YOUR_NAME]`, and `[YOUR_ORGANIZATION]` placeholders — replace them
with your own values.

## Pipeline overview

```
Knowledge base file
    └─► Recursive Character Text Splitter (1500 chars, overlap 200)
            └─► Qdrant upsert
                    └─► Ollama Embeddings — bge-m3:latest (1024 dim)

User message (from WhatsApp via Evolution API)
    └─► Qdrant retriever (same collection)
            └─► Conversational Retrieval QA Chain
                    ├─► ChatGroq / ChatOllama (LLM)
                    └─► BufferMemory (keyed on WhatsApp sender JID)
```

BufferMemory keyed on `sessionId` (the sender's WhatsApp JID) gives each contact
their own conversation history, so the bot maintains context across messages.
