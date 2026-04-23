# WhatsApp RAG Bot — Self-Hosted Starter Kit

A fully self-hosted WhatsApp chatbot that answers questions from your own knowledge base using Retrieval-Augmented Generation (RAG). Built on open-source tools, with Groq as the only paid service (free tier available).

```
WhatsApp ──► Evolution API ──► Flowise ──► Qdrant (vector search)
                                    │
                                    ├──► Ollama / bge-m3 (embeddings)
                                    └──► Groq / llama-3.1 (LLM)
```

**Running costs:** Groq API is free up to generous limits. Everything else runs locally.

---

## Stack

| Service | Role | Image |
|---|---|---|
| [Evolution API](https://github.com/EvolutionAPI/evolution-api) | WhatsApp gateway | `evoapicloud/evolution-api:v2.3.7` |
| [Flowise](https://github.com/FlowiseAI/Flowise) | RAG pipeline orchestration | `flowiseai/flowise:latest` |
| [Qdrant](https://github.com/qdrant/qdrant) | Vector store | `qdrant/qdrant:latest` |
| [Ollama](https://github.com/ollama/ollama) | Local embedding model | `ollama/ollama:latest` |
| [Groq](https://console.groq.com) | LLM inference (cloud) | API only |
| PostgreSQL 15 | Evolution API database | `postgres:15` |
| Redis 7 | Evolution API session cache | `redis:7-alpine` |

---

## Prerequisites

- Linux host (tested on Ubuntu 22.04+, Fedora, Bazzite)
- [Docker](https://docs.docker.com/engine/install/) or [Podman](https://podman.io/docs/installation) with Compose
- At least 8GB RAM (16GB recommended if running Ollama locally)
- A WhatsApp account (will be connected via QR code)
- A free [Groq API key](https://console.groq.com)

---

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/trisanap/whatsapp-rag-bot.git
cd whatsapp-rag-bot
cp .env.example .env
```

Edit `.env` with your values — at minimum:

```env
HOST_IP=192.168.1.x          # your machine's LAN IP (not localhost)
EVOLUTION_API_KEY=...         # any strong random string
FLOWISE_API_KEY=...           # set after Flowise is running
FLOWISE_CHATFLOW_ID=...       # set after importing the chatflow
GROQ_API_KEY=...              # from console.groq.com
```

> **Why `HOST_IP` and not `localhost`?**
> Podman/Docker containers can't resolve `localhost` to the host machine when
> using `--network host`. Use your actual LAN IP (e.g. `192.168.1.4`).
> Find it with: `ip route get 1 | awk '{print $7}'`

### 2. Run setup

```bash
bash scripts/setup.sh
```

This will:
- Start all containers
- Apply the Evolution API browser fingerprint patch (see [Known Issues](#known-issues))
- Pull the `bge-m3:latest` embedding model into Ollama

### 3. Set up Flowise

1. Open Flowise at `http://YOUR_IP:3000`
2. Log in with `FLOWISE_USERNAME` / `FLOWISE_PASSWORD` from your `.env`
3. Go to **Chatflows** → **Import** → select `flowise/chatflow-export.json`
4. Open the imported chatflow and update:
   - **Ollama Embeddings** node → URL: `http://YOUR_IP:11434`
   - **Qdrant** node → URL: `http://YOUR_IP:6333`, Collection: `knowledge_base`
   - **ChatGroq** node → paste your Groq API key, set model to `llama-3.1-8b-instant`
5. In **Document Loader** → upload your knowledge base file (replace the sample in `knowledge-base/`)
6. Save and click **Upsert** to index your knowledge base into Qdrant
7. Go to **Settings** → **API Keys** → create an API key → copy it to `FLOWISE_API_KEY` in `.env`
8. Copy the chatflow ID from the URL bar → paste to `FLOWISE_CHATFLOW_ID` in `.env`

### 4. Connect WhatsApp

1. Open Evolution API Manager at `http://YOUR_IP:8081/manager`
2. Log in with your `EVOLUTION_API_KEY`
3. Create a new instance (name it anything, e.g. `my-bot`)
4. Scan the QR code with your WhatsApp phone
5. Go to **Settings** → enable **Groups Ignore** (prevents the bot from replying in group chats)

### 5. Wire Evolution API to Flowise

In Evolution API Manager:
1. Open your instance → **Settings** → **Chatbot / Flowise**
2. Enter:
   - Flowise URL: `http://YOUR_IP:3000`
   - Chatflow ID: (from `.env`)
   - API Key: (from `.env`)
3. Save — the bot is now live.

Send a WhatsApp message to your connected number and it will answer from your knowledge base.

---

## Auto-start on Boot

### Podman (rootless)

```bash
bash scripts/generate-services.sh
```

This generates systemd user services for all containers so they restart automatically after reboot.

### Docker

The `restart: unless-stopped` policy in `docker-compose.yml` handles this automatically. No extra steps needed.

---

## Updating the Knowledge Base

1. Edit or replace `knowledge-base/knowledge-base.txt` with your new content
2. In Flowise, open your chatflow → Document Loader → upload the updated file
3. Click **Upsert** to re-index
4. The bot immediately uses the updated knowledge base — no restart needed

**Tips for a good knowledge base:**
- Use Q&A format — it matches how users ask questions
- Use clear headings (`## Section`) to help chunking
- Keep related facts together — each chunk should make sense on its own
- Be specific — vague source text produces vague answers
- See `knowledge-base/knowledge-base.txt` for a documented example

---

## LLM Options

You have two choices for the language model. Both work with the same Flowise chatflow — you just swap one node.

### Option A: Groq API (default)

Fast, free tier is generous, no GPU required. Best for getting started quickly or running on low-spec hardware.

1. Get a free API key at [console.groq.com](https://console.groq.com)
2. Set `GROQ_API_KEY` in `.env`
3. In Flowise, use the **ChatGroq** node — set model to `llama-3.1-8b-instant`

| Model | Speed | Quality | Notes |
|---|---|---|---|
| `llama-3.1-8b-instant` | Fastest | Good | Default — best for RAG |
| `llama-3.3-70b-versatile` | Slower | Best | Better quality, still free tier |
| `gemma2-9b-it` | Fast | Good | Strong instruction following |

### Option B: Ollama local LLM (completely free, no API key)

Runs the model on your own GPU. Zero ongoing cost, works fully offline.

**Minimum:** ~6GB VRAM for 7B models (NVIDIA or AMD). CPU-only works but is slow.

**Step 1 — Pull a model:**

```bash
# Best for multilingual / Indonesian
docker exec ollama ollama pull qwen2.5:7b

# Fastest, lowest VRAM (~3–4GB)
docker exec ollama ollama pull llama3.2:3b

# Strong English reasoning
docker exec ollama ollama pull mistral:7b
```

**Step 2 — Enable GPU in `docker-compose.yml`:**

For NVIDIA, uncomment the `deploy` block under the `ollama` service:
```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]
```

For AMD (ROCm), swap the image and uncomment the `devices` block:
```yaml
image: ollama/ollama:rocm
devices:
  - /dev/kfd
  - /dev/dri
```

**Step 3 — Swap the node in Flowise:**

Replace the **ChatGroq** node with **ChatOllama**:
- Base URL: `http://YOUR_IP:11434`
- Model: `qwen2.5:7b` (or whichever you pulled)
- Temperature: `0.1`

| Model | VRAM | Best for |
|---|---|---|
| `qwen2.5:7b` | ~5GB | Multilingual (Indonesian, Malay, English) |
| `llama3.2:3b` | ~3GB | Low-spec machines, simple Q&A |
| `llama3.1:8b` | ~6GB | English-heavy knowledge bases |
| `mistral:7b` | ~5GB | Technical content, structured answers |

> **Tip:** For RAG, a small model at temperature `0.1` often beats a larger model at higher temperatures. The retrieval step does the heavy lifting — the LLM just needs to summarize faithfully from the retrieved chunks.

### Fully free setup (zero API costs)

| Component | Service | Cost |
|---|---|---|
| LLM | Ollama (local) | Free |
| Embeddings | Ollama + bge-m3 | Free |
| Vector store | Qdrant | Free |
| WhatsApp gateway | Evolution API | Free |
| RAG orchestration | Flowise | Free |

The only requirement is a GPU with enough VRAM for your chosen model.

---

## Embedding Options

### Option A: Ollama + bge-m3 (default — local, offline)

`bge-m3:latest` is a strong multilingual embedding model (1024 dimensions). It runs entirely on your machine — no API calls, no cost, works offline. Requires ~1GB RAM.

```bash
# Pull the model (done automatically by setup.sh)
docker exec ollama ollama pull bge-m3:latest

# Or swap for a lighter model:
docker exec ollama ollama pull nomic-embed-text  # 768 dimensions
```

If you change the model, update `QDRANT_VECTOR_DIM` in `.env` and re-create the Qdrant collection before re-indexing.

### Option B: Jina AI API (cloud, free tier)

If you don't want to run Ollama locally (e.g. low-RAM server):

1. Sign up at [jina.ai](https://jina.ai) — free tier includes 1M tokens/month
2. In Flowise, replace the **Ollama Embeddings** node with **JinaAI Embeddings**
3. Set model to `jina-embeddings-v3` (1024 dimensions) — matches bge-m3's dimension
4. Comment out or remove the `ollama` service from `docker-compose.yml`

---

## Customizing Bot Behavior

All bot behavior is configured in Flowise:

- **System prompt** — Edit the system prompt in the Conversational Retrieval QA Chain node to give the bot its persona, rules, and tone
- **Temperature** — Set to `0.1` for strict factual answers, higher for more conversational responses
- **Chunk size / overlap** — Adjust in the Document Loader node (recommended: 1500 / 200)
- **Top K retrieval** — How many chunks to retrieve per query (recommended: 3–5)

The office hours / greeting / allowlist logic from the original `wa-bridge.js` is now handled natively by Evolution API's chatbot settings (you can set a fallback message and active hours in the Manager UI).

---

## Known Issues

### WhatsApp connection rejected on Linux hosts

**Symptom:** Evolution API connects but WhatsApp immediately disconnects.

**Cause:** Evolution API v2.x uses Node.js `os.release()` to build a browser fingerprint. On Linux, this leaks your kernel version string (e.g. `6.x.x-...`) which WhatsApp rejects.

**Fix:** `setup.sh` patches `main.js` and `main.mjs` to hardcode a Windows version string (`10.0.22631`) instead. This patch must be re-applied every time the container is recreated:

```bash
bash scripts/patch-evolution.sh
```

> The os module variable name (`Go`, `Dr`, `nr`, etc.) changes with each image build. The patch script auto-detects it with `grep`.

### Qdrant SELinux volume errors (Fedora/RHEL/Bazzite)

If Qdrant fails to start with permission errors on SELinux hosts, the `:Z` volume labels in `docker-compose.yml` should fix it. If not:

```bash
# Check what's blocking it
sudo ausearch -m avc -ts recent | tail -20
```

---

## Re-running the Patch After Updates

If you update the Evolution API image (`docker compose pull`), re-run:

```bash
docker compose up -d evolution-api
bash scripts/patch-evolution.sh
```

---

## Project Structure

```
.
├── docker-compose.yml          # All services
├── .env.example                # Configuration template (copy to .env)
├── README.md                   # This file
├── flowise/
│   └── chatflow-export.json    # Flowise RAG pipeline (import this)
├── knowledge-base/
│   └── knowledge-base.txt      # Sample knowledge base (replace with yours)
└── scripts/
    ├── setup.sh                # One-shot setup + patch
    ├── patch-evolution.sh      # Re-apply fingerprint patch after updates
    └── generate-services.sh    # Podman: generate systemd user services
```

---

## License

MIT — use freely, attribution appreciated.
