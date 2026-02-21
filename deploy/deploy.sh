#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# ── Load .env ──────────────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: ${ENV_FILE} not found."
  echo "       Copy .env.example to .env and fill in your values."
  exit 1
fi

# Strip Windows carriage returns (\r) before sourcing
ENV_CLEAN=$(mktemp)
tr -d '\r' < "$ENV_FILE" > "$ENV_CLEAN"

set -a
source "$ENV_CLEAN"
set +a
rm -f "$ENV_CLEAN"

# ── Validate required variables ───────────────────────────────────
missing=()
for var in SERVER_IP SSH_USER SSH_KEY DOMAIN_NAME CERTBOT_EMAIL; do
  if [[ -z "${!var:-}" ]]; then
    missing+=("$var")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: The following variables are missing in .env:"
  printf '       - %s\n' "${missing[@]}"
  exit 1
fi

# ── Build a temporary inventory ───────────────────────────────────
INVENTORY=$(mktemp)
trap 'rm -f "$INVENTORY"' EXIT

cat > "$INVENTORY" <<EOF
[webservers]
webserver ansible_host=${SERVER_IP} ansible_user=${SSH_USER} ansible_ssh_private_key_file=${SSH_KEY}
EOF

# ── Determine deploy mode ────────────────────────────────────────
TAGS=""
if [[ "${1:-}" == "content" ]]; then
  TAGS="--tags content"
  shift
fi

# ── Run Ansible ──────────────────────────────────────────────────
cd "$SCRIPT_DIR"
echo "── Inventory ──"
cat "$INVENTORY"
echo "── Extra vars ──"
echo "  server_name=${DOMAIN_NAME}"
echo "  certbot_email=${CERTBOT_EMAIL}"
echo "────────────────"

ansible-playbook \
  -i "$INVENTORY" \
  playbook.yml \
  -e "server_name=${DOMAIN_NAME}" \
  -e "certbot_email=${CERTBOT_EMAIL}" \
  $TAGS \
  "$@"

