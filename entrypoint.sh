#!/bin/bash
set -euo pipefail

export DATA_DIR="${DATA_DIR:-/data}"
export PORT="${PORT:-8080}"
export HOME="${HOME:-/root}"

mkdir -p \
  "$DATA_DIR/db" \
  "$DATA_DIR/redis" \
  "$DATA_DIR/rabbit" \
  "$DATA_DIR/minio" \
  "$DATA_DIR/log" \
  /var/log/supervisor \
  /run/rabbitmq
grep -q " stoat$" /etc/hosts || echo "127.0.0.1 stoat" >> /etc/hosts

# Stable RabbitMQ node identity across restarts
export RABBITMQ_NODENAME="${RABBITMQ_NODENAME:-rabbit@localhost}"
export RABBITMQ_MNESIA_BASE="$DATA_DIR/rabbit/mnesia"
export RABBITMQ_LOG_BASE="$DATA_DIR/log"
export RABBITMQ_CONFIG_FILE="$DATA_DIR/rabbit/rabbitmq"
export RABBITMQ_ENABLED_PLUGINS_FILE="$DATA_DIR/rabbit/enabled_plugins"

# Public hostname used in Revolt.toml + the web client
resolve_domain() {
  if [ -n "${DOMAIN:-}" ]; then
    echo "$DOMAIN"
    return
  fi
  if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
    echo "$RAILWAY_PUBLIC_DOMAIN"
    return
  fi
  if [ -n "${RAILWAY_STATIC_URL:-}" ]; then
    echo "${RAILWAY_STATIC_URL#https://}"
    return
  fi
  echo "localhost:${PORT}"
}

export DOMAIN="$(resolve_domain)"
echo "Public domain: $DOMAIN"

/generate_runtime_config.sh
set -a
source "$DATA_DIR/secrets.env"
set +a
export MINIO_ROOT_USER MINIO_ROOT_PASSWORD RABBITMQ_DEFAULT_USER RABBITMQ_DEFAULT_PASS

wait_for_port() {
  local host="$1" port="$2" name="$3" tries="${4:-60}"
  echo "Waiting for $name on $host:$port ..."
  for _ in $(seq 1 "$tries"); do
    if nc -z "$host" "$port" 2>/dev/null; then
      echo "$name is up"
      return 0
    fi
    sleep 1
  done
  echo "WARNING: $name did not become ready on $host:$port" >&2
  return 1
}

# Start infrastructure first so app processes can connect immediately.
supervisord -c /etc/supervisor/supervisord.conf &
SUPERVISOR_PID=$!

sleep 2
supervisorctl start redis mongo rabbit minio || true

wait_for_port 127.0.0.1 6379 redis || true
wait_for_port 127.0.0.1 27017 mongo || true
wait_for_port 127.0.0.1 5672 rabbit || true
wait_for_port 127.0.0.1 9000 minio || true

echo "Ensuring MinIO bucket revolt-uploads exists"
mc alias set local http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1 || true
mc mb --ignore-existing local/revolt-uploads >/dev/null 2>&1 || true

supervisorctl start autumn january gifbox api events crond pushd web caddy || true

echo
echo "=============================================="
echo " Stoat is starting"
echo " URL: https://$DOMAIN"
echo " First user to register owns the instance."
echo " Voice/video is disabled in this Railway build."
echo " Secrets live in $DATA_DIR/secrets.env — back them up."
echo "=============================================="
echo

# Keep PID 1 as supervisord
wait "$SUPERVISOR_PID"
