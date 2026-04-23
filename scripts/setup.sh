#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# setup.sh — One-shot setup for WhatsApp RAG Bot
#
# What this script does:
#   1. Validates your .env file
#   2. Starts all Docker/Podman containers
#   3. Waits for Evolution API to be ready
#   4. Patches the WhatsApp browser fingerprint (os.release fix)
#   5. Pulls the Ollama embedding model
#   6. Prints next steps
#
# Usage: bash setup.sh
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Color helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[setup]${RESET} $*"; }
success() { echo -e "${GREEN}[setup]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[setup]${RESET} $*"; }
error()   { echo -e "${RED}[setup] ERROR:${RESET} $*" >&2; exit 1; }

# ── Detect container runtime ──────────────────────────────────────────────────
if command -v podman &>/dev/null; then
  RUNTIME=podman
  COMPOSE="podman-compose"
elif command -v docker &>/dev/null; then
  RUNTIME=docker
  COMPOSE="docker compose"
else
  error "Neither Docker nor Podman found. Please install one first."
fi
info "Using container runtime: ${BOLD}$RUNTIME${RESET}"

# ── Check .env exists ─────────────────────────────────────────────────────────
if [[ ! -f .env ]]; then
  warn ".env not found — copying from .env.example"
  cp .env.example .env
  warn "Please edit .env with your actual values, then re-run this script."
  exit 1
fi

# ── Load .env ─────────────────────────────────────────────────────────────────
set -a; source .env; set +a

# ── Validate required variables ───────────────────────────────────────────────
REQUIRED_VARS=(HOST_IP EVOLUTION_API_KEY FLOWISE_CHATFLOW_ID FLOWISE_API_KEY GROQ_API_KEY)
for var in "${REQUIRED_VARS[@]}"; do
  val="${!var:-}"
  if [[ -z "$val" || "$val" == *"paste-your"* || "$val" == *"change-this"* ]]; then
    error "$var is not set or still has the placeholder value. Edit your .env file."
  fi
done
success "All required .env variables are set."

# ── Start containers ──────────────────────────────────────────────────────────
info "Starting containers..."
$COMPOSE up -d
success "Containers started."

# ── Wait for Evolution API ────────────────────────────────────────────────────
EVOLUTION_URL="http://${HOST_IP}:${EVOLUTION_PORT:-8081}"
info "Waiting for Evolution API at ${EVOLUTION_URL}..."
for i in $(seq 1 30); do
  if curl -sf "${EVOLUTION_URL}/" -o /dev/null 2>/dev/null; then
    success "Evolution API is up."
    break
  fi
  if [[ $i -eq 30 ]]; then
    error "Evolution API didn't start after 60s. Check logs: ${RUNTIME} logs evolution-api"
  fi
  sleep 2
done

# ── Patch WhatsApp browser fingerprint ───────────────────────────────────────
#
# Evolution API v2.x uses Node's os.release() to build a WhatsApp browser
# fingerprint. On Linux hosts, the kernel version leaks (e.g. 6.x.x-...) and
# WhatsApp rejects the connection. We patch main.js and main.mjs to hardcode
# a Windows version string instead.
#
info "Patching Evolution API browser fingerprint (os.release fix)..."

patch_file() {
  local file="$1"
  if ! $RUNTIME exec evolution-api test -f "$file" 2>/dev/null; then
    warn "  $file not found — skipping."
    return
  fi

  # Find the os module variable name (changes per build: Go, Dr, nr, etc.)
  local os_var
  os_var=$($RUNTIME exec evolution-api grep -o '[a-z][a-z]*=require("os")' "$file" 2>/dev/null \
    | head -1 | cut -d= -f1)

  if [[ -z "$os_var" ]]; then
    warn "  Could not detect os module variable in $file — skipping."
    return
  fi

  info "  Detected os module variable: ${BOLD}${os_var}${RESET} in $file"

  # Check if already patched
  if $RUNTIME exec evolution-api grep -q '"10.0.22631"' "$file" 2>/dev/null; then
    success "  $file already patched."
    return
  fi

  # Replace (0,XX.release)() with the hardcoded Windows version string
  $RUNTIME exec evolution-api \
    sed -i "s/(0,${os_var}\.release)()/\"10.0.22631\"/g" "$file"

  if $RUNTIME exec evolution-api grep -q '"10.0.22631"' "$file" 2>/dev/null; then
    success "  Patched $file successfully."
  else
    warn "  Patch may not have applied to $file — verify manually."
  fi
}

patch_file "/evolution/dist/main.js"
patch_file "/evolution/dist/main.mjs"

# Restart Evolution API so the patch takes effect
info "Restarting Evolution API to apply patch..."
$RUNTIME restart evolution-api
sleep 5
success "Evolution API restarted."

# ── Pull Ollama embedding model ───────────────────────────────────────────────
EMBED_MODEL="${OLLAMA_EMBED_MODEL:-bge-m3:latest}"
info "Pulling Ollama embedding model: ${BOLD}${EMBED_MODEL}${RESET}"
info "(This may take a few minutes on first run...)"
$RUNTIME exec ollama ollama pull "$EMBED_MODEL"
success "Embedding model ready."

# ── Pull Ollama LLM model (optional) ─────────────────────────────────────────
# Only pulled if OLLAMA_LLM_MODEL is set AND doesn't look like the placeholder
LLM_MODEL="${OLLAMA_LLM_MODEL:-}"
if [[ -n "$LLM_MODEL" && "$LLM_MODEL" != *"paste"* && "$LLM_MODEL" != *"change"* ]]; then
  info "Pulling Ollama LLM model: ${BOLD}${LLM_MODEL}${RESET}"
  info "(This may take several minutes depending on model size...)"
  $RUNTIME exec ollama ollama pull "$LLM_MODEL"
  success "LLM model ready: ${LLM_MODEL}"
else
  info "OLLAMA_LLM_MODEL not set — skipping local LLM pull (using Groq by default)."
  info "To use a local LLM, set OLLAMA_LLM_MODEL in .env and re-run this script."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}✓ Setup complete!${RESET}"
echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo -e "  1. Open Flowise at ${CYAN}http://${HOST_IP}:${FLOWISE_PORT:-3000}${RESET}"
echo -e "     Import the chatflow from ${BOLD}flowise/chatflow-export.json${RESET}"
echo -e "     Then upload your knowledge base file via the Document Loader node."
echo ""
echo -e "  2. Open Evolution API Manager at ${CYAN}http://${HOST_IP}:${EVOLUTION_PORT:-8081}/manager${RESET}"
echo -e "     Create an instance named '${BOLD}${EVOLUTION_INSTANCE_NAME:-my-bot}${RESET}'"
echo -e "     Scan the QR code to connect WhatsApp."
echo -e "     Enable 'Groups Ignore' in Settings to prevent group chat replies."
echo ""
echo -e "  3. Configure the native Flowise integration in Evolution API Manager:"
echo -e "     Instance > Settings > Flowise > enter chatflow ID and API key."
echo ""
echo -e "  See ${BOLD}README.md${RESET} for full configuration details."
echo ""
