#!/bin/bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
SECRETS="$DATA_DIR/secrets.env"
DOMAIN="${DOMAIN:-localhost}"
PORT="${PORT:-8080}"

if [ ! -f "$SECRETS" ]; then
  echo "Generating new secrets at $SECRETS"
  TMPPEM="$(mktemp)"
  openssl ecparam -name prime256v1 -genkey -noout -out "$TMPPEM"
  VAPID_PRIVATE="$(base64 -w0 "$TMPPEM" | tr -d '=')"
  VAPID_PUBLIC="$(openssl ec -in "$TMPPEM" -outform DER 2>/dev/null | tail --bytes 65 | base64 -w0 | tr '/+' '_-' | tr -d '=' | tr -d '\n')"
  rm -f "$TMPPEM"
  FILES_KEY="$(openssl rand -base64 32)"
  MINIO_ROOT_USER="stoat$(openssl rand -hex 4)"
  MINIO_ROOT_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=')"
  RABBITMQ_DEFAULT_USER="stoat"
  RABBITMQ_DEFAULT_PASS="$(openssl rand -base64 24 | tr -d '/+=')"

  cat > "$SECRETS" <<EOF
# Generated on first boot. Losing this file makes uploaded files unreadable.
REVOLT__PUSHD__VAPID__PRIVATE_KEY='${VAPID_PRIVATE}'
REVOLT__PUSHD__VAPID__PUBLIC_KEY='${VAPID_PUBLIC}'
REVOLT__FILES__ENCRYPTION_KEY='${FILES_KEY}'
MINIO_ROOT_USER='${MINIO_ROOT_USER}'
MINIO_ROOT_PASSWORD='${MINIO_ROOT_PASSWORD}'
RABBITMQ_DEFAULT_USER='${RABBITMQ_DEFAULT_USER}'
RABBITMQ_DEFAULT_PASS='${RABBITMQ_DEFAULT_PASS}'
EOF
  chmod 600 "$SECRETS"
else
  echo "Reusing secrets from $SECRETS"
fi

# shellcheck disable=SC1090
set -a
# secrets.env uses single quotes; source them
# shellcheck disable=SC1091
source "$SECRETS"
set +a

# Domain is needed by run-stoat.sh / the web injector
grep -q '^DOMAIN=' "$SECRETS" 2>/dev/null || echo "DOMAIN='${DOMAIN}'" >> "$SECRETS"
sed -i "s|^DOMAIN=.*|DOMAIN='${DOMAIN}'|" "$SECRETS"

cat > /Revolt.toml <<EOF
production = true
disable_events_dont_use = false
environment = "production"

[database]
mongodb = "mongodb://127.0.0.1:27017"
redis   = "redis://127.0.0.1:6379/"

[hosts]
app     = "https://${DOMAIN}"
api     = "https://${DOMAIN}/api"
events  = "wss://${DOMAIN}/ws"
autumn  = "https://${DOMAIN}/autumn"
january = "https://${DOMAIN}/january"
gifbox  = "https://${DOMAIN}/gifbox"
voso_legacy = ""
voso_legacy_ws = ""

[hosts.livekit]

[rabbit]
host = "127.0.0.1"
port = 5672
username = "${RABBITMQ_DEFAULT_USER}"
password = "${RABBITMQ_DEFAULT_PASS}"
default_exchange = "revolt.default"

[rabbit.queues]
acks = "internal.ack"

[api]

[api.registration]
invite_only = ${INVITE_ONLY:-false}

[api.smtp]
host = ""
username = ""
password = ""
from_address = "noreply@${DOMAIN}"
expire_verification = 604800
expire_password_reset = 86400
expire_account_deletion = 86400

[api.security]
authifier_shield_key = ""
trust_cloudflare = true
easypwned = ""
tenor_key = ""
admin_keys = []

[api.security.captcha]
hcaptcha_key = ""
hcaptcha_sitekey = ""

[api.security.shield]
host = ""
key = ""

[api.workers]
max_concurrent_connections = 50

[api.livekit]
call_ring_duration = 30

[api.livekit.nodes]

[api.audit_logs]
expires_after = 2592000

[api.users]
min_username_length = 2

[pushd]
production = true
mass_mention_chunk_size = 200
render_cache_time = 60
exchange = "revolt.notifications"
message_queue = "notifications.origin.message"
mass_mention_queue = "notifications.origin.mass_mention"
fr_accepted_queue = "notifications.ingest.fr_accepted"
fr_received_queue = "notifications.ingest.fr_received"
dm_call_queue = "notifications.ingest.dm_call"
generic_queue = "notifications.ingest.generic"
ack_queue = "notifications.process.ack"

[pushd.vapid]
queue = "notifications.outbound.vapid"
private_key = "${REVOLT__PUSHD__VAPID__PRIVATE_KEY}"
public_key = "${REVOLT__PUSHD__VAPID__PUBLIC_KEY}"

[pushd.fcm]
queue = "notifications.outbound.fcm"
key_type = ""
project_id = ""
private_key_id = ""
private_key = ""
client_email = ""
client_id = ""
auth_uri = ""
token_uri = ""
auth_provider_x509_cert_url = ""
client_x509_cert_url = ""

[pushd.apn]
sandbox = false
queue = "notifications.outbound.apn"
pkcs8 = ""
key_id = ""
team_id = ""

[january]
blocked_domains = []

[files]
encryption_key = "${REVOLT__FILES__ENCRYPTION_KEY}"
webp_quality = 80.0
blocked_mime_types = []
clamd_host = ""
scan_mime_types = []

[files.limit]
min_file_size = 1
min_resolution = [1, 1]
max_mega_pixels = 40
max_pixel_side = 10_000

[files.preview]
attachments = [1280, 1280]
avatars = [128, 128]
backgrounds = [1280, 720]
icons = [128, 128]
banners = [480, 480]
emojis = [128, 128]

[files.s3]
endpoint = "http://127.0.0.1:9000"
path_style_buckets = true
region = "minio"
access_key_id = "${MINIO_ROOT_USER}"
secret_access_key = "${MINIO_ROOT_PASSWORD}"
default_bucket = "revolt-uploads"

[features]
webhooks_enabled = false
mass_mentions_send_notifications = true
mass_mentions_enabled = true

[features.limits]

[features.limits.global]
group_size = 100
message_embeds = 5
message_replies = 5
message_reactions = 20
server_emoji = 100
server_roles = 200
server_channels = 200
new_user_hours = 72
body_limit_size = 20_000_000
restrict_server_creation = []
max_invite_duration_days = 30

[features.limits.new_user]
outgoing_friend_requests = 5
bots = 2
message_length = 2000
message_attachments = 5
servers = 50
voice_quality = 16000
video = false
video_resolution = [1280, 720]
video_aspect_ratio = [0.3, 2.5]

[features.limits.new_user.file_upload_size_limit]
attachments = 20_000_000
avatars = 4_000_000
backgrounds = 6_000_000
icons = 2_500_000
banners = 6_000_000
emojis = 500_000

[features.limits.default]
outgoing_friend_requests = 10
bots = 5
message_length = 2000
message_attachments = 5
servers = 100
voice_quality = 16000
video = false
video_resolution = [1280, 720]
video_aspect_ratio = [0.3, 2.5]

[features.limits.default.file_upload_size_limit]
attachments = 20_000_000
avatars = 4_000_000
backgrounds = 6_000_000
icons = 2_500_000
banners = 6_000_000
emojis = 500_000

[features.advanced]
process_message_delay_limit = 5
seen_events_cache_size = 2048

[features.legal_links]
terms_of_service = ""
privacy_policy = ""
guidelines = ""

[sentry]
api = ""
events = ""
voice_ingress = ""
files = ""
proxy = ""
pushd = ""
crond = ""
gifbox = ""
EOF

# Caddy listens on Railway's $PORT (HTTP). Railway terminates TLS.
sed "s/__PORT__/${PORT}/g" /etc/caddy/Caddyfile.template > /etc/caddy/Caddyfile

mkdir -p /stoat.json
printf '{"api":"https://%s/api"}' "$DOMAIN" > /stoat.json/index.json
# file_server root is a directory; also keep a copy at /stoat.json file path used by some setups
printf '{"api":"https://%s/api"}' "$DOMAIN" > /opt/stoat.json

# Web client injection env (also set in supervisor)
export VITE_HOST="$DOMAIN"
export VITE_API_URL="https://${DOMAIN}/api"
export VITE_DEV_WS_URL="wss://${DOMAIN}/ws"
export VITE_DEV_MEDIA_URL="https://${DOMAIN}/autumn"
export VITE_DEV_PROXY_URL="https://${DOMAIN}/january"
export VITE_DEV_GIFBOX_URL="https://${DOMAIN}/gifbox"
