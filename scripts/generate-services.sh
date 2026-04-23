#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# generate-services.sh — Generate systemd user services for all containers
#
# This ensures all containers auto-start on boot (Podman rootless).
# Docker users can skip this — Docker handles auto-restart natively.
#
# Usage: bash scripts/generate-services.sh
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[services]${RESET} $*"; }
success() { echo -e "${GREEN}[services]${RESET} $*"; }

if ! command -v podman &>/dev/null; then
  echo "This script is for Podman rootless only. Docker users: containers restart automatically."
  exit 0
fi

SERVICES_DIR="${HOME}/.config/systemd/user"
mkdir -p "$SERVICES_DIR"

CONTAINERS=(
  evolution-postgres
  evolution-redis
  evolution-api
  flowise
  qdrant
  ollama
)

for container in "${CONTAINERS[@]}"; do
  if ! podman container exists "$container" 2>/dev/null; then
    info "Container $container not found — skipping (run setup.sh first)."
    continue
  fi

  info "Generating service for: ${BOLD}${container}${RESET}"
  podman generate systemd \
    --name \
    --restart-policy=unless-stopped \
    --files \
    --output-dir "$SERVICES_DIR" \
    "$container"
done

systemctl --user daemon-reload

for container in "${CONTAINERS[@]}"; do
  svc="container-${container}.service"
  if [[ -f "${SERVICES_DIR}/${svc}" ]]; then
    systemctl --user enable "$svc" 2>/dev/null || true
    success "Enabled: $svc"
  fi
done

# Enable linger so services start at boot even without login
loginctl enable-linger "$USER" 2>/dev/null || true

success "All services enabled. Containers will start automatically on boot."
info "To check status: systemctl --user status container-evolution-api.service"
