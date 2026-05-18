#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

die() {
  echo "Error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

need_cmd docker
need_cmd openssl
need_cmd sudo

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
else
  die "Missing Docker Compose. Install 'docker compose' plugin or 'docker-compose'."
fi

OS="$(uname -s)"
case "$OS" in
  Darwin)
    PLATFORM="macOS"
    DEFAULT_BASE="${HOME}/anythingllm-stack"
    ;;
  Linux)
    PLATFORM="Linux"
    DEFAULT_BASE="${HOME}/anythingllm-stack"
    ;;
  *)
    die "Unsupported OS: ${OS}"
    ;;
esac

DEFAULT_ANYTHINGLLM_STORAGE="${DEFAULT_BASE}/storage/anythingllm"
DEFAULT_POSTGRES_STORAGE="${DEFAULT_BASE}/storage/postgres"

mkdir -p ./secrets ./postgres ./scripts
chmod 700 ./secrets

echo "Detected ${PLATFORM}."
echo
echo "Default paths:"
echo "  ANYTHINGLLM_STORAGE=${DEFAULT_ANYTHINGLLM_STORAGE}"
echo "  POSTGRES_STORAGE=${DEFAULT_POSTGRES_STORAGE}"
echo

read -r -p "Use these paths? [Y/n]: " use_defaults
use_defaults="${use_defaults:-Y}"

if [[ ! "${use_defaults}" =~ ^[Yy]$ ]]; then
  read -r -p "Enter ANYTHINGLLM_STORAGE path: " ANYTHINGLLM_STORAGE
  read -r -p "Enter POSTGRES_STORAGE path: " POSTGRES_STORAGE
else
  ANYTHINGLLM_STORAGE="${DEFAULT_ANYTHINGLLM_STORAGE}"
  POSTGRES_STORAGE="${DEFAULT_POSTGRES_STORAGE}"
fi

mkdir -p "${ANYTHINGLLM_STORAGE}" "${POSTGRES_STORAGE}"
touch "${ANYTHINGLLM_STORAGE}/.env"

cat > .env <<EOF
ANYTHINGLLM_STORAGE=${ANYTHINGLLM_STORAGE}
POSTGRES_STORAGE=${POSTGRES_STORAGE}
EOF

chmod 600 .env
echo "Wrote .env"

if [ -f ./secrets/postgres_password.txt ]; then
  echo "Secret already exists: secrets/postgres_password.txt"
else
  echo "Generating PostgreSQL password..."
  PASSWORD="$(openssl rand -base64 32 | tr -d '/+=\n' | cut -c1-32)"
  printf "%s" "${PASSWORD}" > ./secrets/postgres_password.txt
  chmod 600 ./secrets/postgres_password.txt
  echo "Wrote secrets/postgres_password.txt"
fi

read -r -p "Add hosts entry for anythingllm.localhost -> 127.0.0.1? [Y/n]: " add_hosts
add_hosts="${add_hosts:-Y}"
if [[ "${add_hosts}" =~ ^[Yy]$ ]]; then
  HOSTS_LINE="127.0.0.1 anythingllm.localhost"
  if grep -qxF "${HOSTS_LINE}" /etc/hosts 2>/dev/null; then
    echo "Hosts entry already present."
  else
    echo "Adding hosts entry (sudo required)..."
    echo "${HOSTS_LINE}" | sudo tee -a /etc/hosts >/dev/null
    if [ "${OS}" = "Darwin" ]; then
      sudo dscacheutil -flushcache || true
      sudo killall -HUP mDNSResponder || true
    fi
    echo "Hosts entry added."
  fi
fi

read -r -p "Enter a public domain for Caddy (leave blank to skip): " PUBLIC_DOMAIN
PUBLIC_DOMAIN="${PUBLIC_DOMAIN:-}"

if [ -n "${PUBLIC_DOMAIN}" ]; then
  TEMPLATE="./Caddyfile.public.tmpl"
  [ -f "${TEMPLATE}" ] || die "Missing template: ${TEMPLATE}"
  # Escape sed-special chars in the domain ( & / \ )
  ESCAPED_DOMAIN="$(printf '%s' "${PUBLIC_DOMAIN}" | sed -e 's/[\/&]/\\&/g')"
  sed "s/{{PUBLIC_DOMAIN}}/${ESCAPED_DOMAIN}/g" "${TEMPLATE}" > ./Caddyfile.public
  chmod 644 ./Caddyfile.public
  echo "Rendered Caddyfile.public from template for ${PUBLIC_DOMAIN}"
else
  echo "No public domain configured; local HTTPS mode is ready."
fi

echo
echo "Setup complete."
echo "You can override the generated paths by editing .env."
echo "Current values:"
echo "  ANYTHINGLLM_STORAGE=${ANYTHINGLLM_STORAGE}"
echo "  POSTGRES_STORAGE=${POSTGRES_STORAGE}"
echo
echo "Next steps:"
echo "  Local mode:  ./scripts/stack.sh local up -d"
echo "  Public mode: ./scripts/stack.sh public up -d"
