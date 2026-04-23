#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# patch-evolution.sh — Re-apply the WhatsApp browser fingerprint patch
#
# Run this EVERY TIME the evolution-api container is recreated (e.g. after
# docker compose pull, or after updating the image). The patch does not
# persist across container rebuilds.
#
# Usage: bash scripts/patch-evolution.sh
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[patch]${RESET} $*"; }
success() { echo -e "${GREEN}[patch]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[patch]${RESET} $*"; }

RUNTIME=$(command -v podman &>/dev/null && echo podman || echo docker)

patch_file() {
  local file="$1"

  if ! $RUNTIME exec evolution-api test -f "$file" 2>/dev/null; then
    warn "$file not found — skipping."
    return
  fi

  local os_var
  os_var=$($RUNTIME exec evolution-api grep -o '[a-z][a-z]*=require("os")' "$file" 2>/dev/null \
    | head -1 | cut -d= -f1)

  if [[ -z "$os_var" ]]; then
    warn "Could not detect os module variable in $file"
    return
  fi

  info "os module variable: ${BOLD}${os_var}${RESET} in $(basename $file)"

  if $RUNTIME exec evolution-api grep -q '"10.0.22631"' "$file" 2>/dev/null; then
    success "$(basename $file) already patched."
    return
  fi

  $RUNTIME exec evolution-api \
    sed -i "s/(0,${os_var}\.release)()/\"10.0.22631\"/g" "$file"

  success "Patched $(basename $file)"
}

info "Patching Evolution API v2.x browser fingerprint..."
patch_file "/evolution/dist/main.js"
patch_file "/evolution/dist/main.mjs"

info "Restarting evolution-api..."
$RUNTIME restart evolution-api
success "Done. WhatsApp fingerprint patch applied."
