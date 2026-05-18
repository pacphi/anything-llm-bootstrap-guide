#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-local}"
shift || true

case "$MODE" in
  local)
    CADDYFILE_PATH="./Caddyfile.local"
    ;;
  public)
    CADDYFILE_PATH="./Caddyfile.public"
    ;;
  *)
    echo "Usage: $0 {local|public} [docker compose args...]"
    exit 1
    ;;
esac

ENV_FILE="./.env"
touch "$ENV_FILE"
if grep -q '^CADDYFILE_PATH=' "$ENV_FILE"; then
  # Portable in-place edit (GNU and BSD sed)
  tmp="$(mktemp)"
  sed "s|^CADDYFILE_PATH=.*|CADDYFILE_PATH=${CADDYFILE_PATH}|" "$ENV_FILE" > "$tmp" && mv "$tmp" "$ENV_FILE"
else
  printf 'CADDYFILE_PATH=%s\n' "$CADDYFILE_PATH" >> "$ENV_FILE"
fi

set -a
. "$ENV_FILE"
set +a

docker compose "$@"
