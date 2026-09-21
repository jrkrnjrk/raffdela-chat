#!/bin/bash
set -euo pipefail
if [ -f /data/secrets.env ]; then
  set -a
  # shellcheck disable=SC1091
  source /data/secrets.env
  set +a
fi
export VITE_HOST="${DOMAIN:-}"
export VITE_API_URL="https://${DOMAIN}/api"
export VITE_DEV_WS_URL="wss://${DOMAIN}/ws"
export VITE_DEV_MEDIA_URL="https://${DOMAIN}/autumn"
export VITE_DEV_PROXY_URL="https://${DOMAIN}/january"
export VITE_DEV_GIFBOX_URL="https://${DOMAIN}/gifbox"
exec "$@"
