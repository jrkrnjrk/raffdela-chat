# Stoat all-in-one image for a single Railway service.
# Copies official Stoat binaries and runs Mongo/Redis/Rabbit/MinIO/Caddy
# in one container. Voice/LiveKit is omitted (Railway has no inbound UDP).

ARG STOAT_BACKEND=v0.15.5
ARG STOAT_WEB=4017c18

FROM ghcr.io/stoatchat/api:${STOAT_BACKEND} AS api
FROM ghcr.io/stoatchat/events:${STOAT_BACKEND} AS events
FROM ghcr.io/stoatchat/file-server:${STOAT_BACKEND} AS autumn
FROM ghcr.io/stoatchat/proxy:${STOAT_BACKEND} AS january
FROM ghcr.io/stoatchat/gifbox:${STOAT_BACKEND} AS gifbox
FROM ghcr.io/stoatchat/crond:${STOAT_BACKEND} AS crond
FROM ghcr.io/stoatchat/pushd:${STOAT_BACKEND} AS pushd
FROM ghcr.io/stoatchat/for-web:${STOAT_WEB} AS web

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    HOSTNAME=stoat \
    PORT=8080 \
    DATA_DIR=/data \
    REVOLT_CONFIG=/Revolt.toml

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        xz-utils \
        openssl \
        supervisor \
        redis-server \
        rabbitmq-server \
        nodejs \
        npm \
        libdav1d6 \
        procps \
        netcat-openbsd \
        python3 \
    && rm -rf /var/lib/apt/lists/*

# MongoDB 7 community server (official tarball — not in Debian repos)
ARG MONGO_VERSION=7.0.14
RUN curl -fsSL "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu2204-${MONGO_VERSION}.tgz" \
        -o /tmp/mongo.tgz \
    && tar -C /tmp -xzf /tmp/mongo.tgz \
    && mv /tmp/mongodb-linux-x86_64-ubuntu2204-${MONGO_VERSION}/bin/mongod /usr/local/bin/mongod \
    && mv /tmp/mongodb-linux-x86_64-ubuntu2204-${MONGO_VERSION}/bin/mongosh /usr/local/bin/mongosh || true \
    && rm -rf /tmp/mongo.tgz /tmp/mongodb-linux-x86_64-ubuntu2204-${MONGO_VERSION}

# MinIO + client
RUN curl -fsSL https://dl.min.io/server/minio/release/linux-amd64/minio -o /usr/local/bin/minio \
    && curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc \
    && chmod +x /usr/local/bin/minio /usr/local/bin/mc

# Caddy
ARG CADDY_VERSION=2.8.4
RUN curl -fsSL "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz" \
        -o /tmp/caddy.tgz \
    && tar -C /usr/local/bin -xzf /tmp/caddy.tgz caddy \
    && rm /tmp/caddy.tgz

# Official Stoat binaries (paths in distroless images are /revolt-*)
COPY --from=api     /revolt-delta   /usr/local/bin/revolt-delta
COPY --from=events  /revolt-bonfire /usr/local/bin/revolt-bonfire
COPY --from=autumn  /revolt-autumn  /usr/local/bin/revolt-autumn
COPY --from=january /revolt-january /usr/local/bin/revolt-january
COPY --from=gifbox  /revolt-gifbox  /usr/local/bin/revolt-gifbox
COPY --from=crond   /revolt-crond   /usr/local/bin/revolt-crond
COPY --from=pushd   /revolt-pushd   /usr/local/bin/revolt-pushd
COPY --from=autumn  /usr/local/bin/ffmpeg  /usr/local/bin/ffmpeg
COPY --from=autumn  /usr/local/bin/ffprobe /usr/local/bin/ffprobe

# Web client (copy sources only — alpine node_modules are not usable on glibc)
COPY --from=web /app/dist /opt/stoat-web/dist
COPY --from=web /app/inject.js /opt/stoat-web/inject.js
COPY --from=web /app/package.json /opt/stoat-web/package.json
RUN cd /opt/stoat-web && npm install --omit=dev

COPY entrypoint.sh /entrypoint.sh
COPY generate_runtime_config.sh /generate_runtime_config.sh
COPY bin/run-stoat.sh /usr/local/bin/run-stoat.sh
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY Caddyfile.template /etc/caddy/Caddyfile.template

RUN chmod +x /entrypoint.sh /generate_runtime_config.sh /usr/local/bin/run-stoat.sh /usr/local/bin/revolt-* \
    && mkdir -p /var/log/supervisor /etc/supervisor/conf.d

EXPOSE 8080
VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=5 \
    CMD curl -fsS "http://127.0.0.1:${PORT:-8080}/" >/dev/null || exit 1

CMD ["/entrypoint.sh"]
