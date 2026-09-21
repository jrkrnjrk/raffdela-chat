# Stoat all-in-one image for a single Railway service.
FROM ghcr.io/stoatchat/api:v0.15.5 AS api
FROM ghcr.io/stoatchat/events:v0.15.5 AS events
FROM ghcr.io/stoatchat/file-server:v0.15.5 AS autumn
FROM ghcr.io/stoatchat/proxy:v0.15.5 AS january
FROM ghcr.io/stoatchat/gifbox:v0.15.5 AS gifbox
FROM ghcr.io/stoatchat/crond:v0.15.5 AS crond
FROM ghcr.io/stoatchat/pushd:v0.15.5 AS pushd
FROM ghcr.io/stoatchat/for-web:4017c18 AS web

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    HOSTNAME=stoat \
    PORT=8080 \
    DATA_DIR=/data \
    REVOLT_CONFIG=/Revolt.toml

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl xz-utils openssl supervisor redis-server \
        rabbitmq-server nodejs npm libdav1d6 ffmpeg procps netcat-openbsd python3 \
    && rm -rf /var/lib/apt/lists/*

ARG MONGO_VERSION=7.0.14
RUN curl -fsSL "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu2204-${MONGO_VERSION}.tgz" \
        -o /tmp/mongo.tgz \
    && tar -C /tmp -xzf /tmp/mongo.tgz \
    && mv /tmp/mongodb-linux-x86_64-ubuntu2204-${MONGO_VERSION}/bin/mongod /usr/local/bin/mongod \
    && rm -rf /tmp/mongo.tgz /tmp/mongodb-linux-x86_64-ubuntu2204-${MONGO_VERSION}

ARG CADDY_VERSION=2.8.4
RUN curl -fsSL "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz" \
        -o /tmp/caddy.tgz \
    && tar -C /usr/local/bin -xzf /tmp/caddy.tgz caddy \
    && rm /tmp/caddy.tgz

RUN curl -fsSL "https://github.com/golithus/minio-builds/releases/download/RELEASE.2025-10-15T17-29-55Z/minio-linux-amd64" \
        -o /usr/local/bin/minio \
    && curl -fsSL "https://github.com/golithus/minio-builds/releases/download/mc-RELEASE.2025-08-13T08-35-41Z/mc-linux-amd64" \
        -o /usr/local/bin/mc \
    && chmod +x /usr/local/bin/minio /usr/local/bin/mc

COPY --from=api      /home/nonroot/revolt-delta   /usr/local/bin/revolt-delta
COPY --from=events   /home/nonroot/revolt-bonfire /usr/local/bin/revolt-bonfire
COPY --from=autumn   /home/nonroot/revolt-autumn  /usr/local/bin/revolt-autumn
COPY --from=january  /home/nonroot/revolt-january /usr/local/bin/revolt-january
COPY --from=gifbox   /home/nonroot/revolt-gifbox  /usr/local/bin/revolt-gifbox
COPY --from=crond    /home/nonroot/revolt-crond   /usr/local/bin/revolt-crond
COPY --from=pushd    /home/nonroot/revolt-pushd   /usr/local/bin/revolt-pushd

COPY --from=web /app/dist /opt/stoat-web/dist
COPY --from=web /app/inject.js /opt/stoat-web/inject.js
COPY --from=web /app/package.json /opt/stoat-web/package.json
RUN cd /opt/stoat-web && npm install --omit=dev

COPY entrypoint.sh /entrypoint.sh
COPY generate_runtime_config.sh /generate_runtime_config.sh
COPY bin/run-stoat.sh /usr/local/bin/run-stoat.sh
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY Caddyfile.template /etc/caddy/Caddyfile.template

RUN chmod +x /entrypoint.sh /generate_runtime_config.sh /usr/local/bin/run-stoat.sh \
        /usr/local/bin/revolt-delta /usr/local/bin/revolt-bonfire \
        /usr/local/bin/revolt-autumn /usr/local/bin/revolt-january \
        /usr/local/bin/revolt-gifbox /usr/local/bin/revolt-crond \
        /usr/local/bin/revolt-pushd /usr/local/bin/minio /usr/local/bin/mc \
    && mkdir -p /var/log/supervisor /etc/supervisor/conf.d

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=5 \
    CMD curl -fsS http://127.0.0.1:8080/ >/dev/null || exit 1
CMD ["/entrypoint.sh"]
