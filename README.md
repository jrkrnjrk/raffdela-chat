# Stoat on Railway (single service)

All-in-one image: web UI, API, websocket, file server, metadata proxy, MongoDB, Redis, RabbitMQ, MinIO, and Caddy in **one container**.

This is an unofficial wrapper around the official Stoat images (`v0.15.5` backend, `for-web` `4017c18`).

**Not included:** voice/video (LiveKit). Railway has no inbound UDP.

**RAM:** give the service **at least 8 GB**. 4 GB will OOM.

## Deploy on Railway

1. Create a GitHub repo and upload everything in this folder (or unzip and `git push`).
2. [railway.app](https://railway.app) → **New project** → **Deploy from GitHub repo**.
3. **Before the first successful boot**, add a volume:
   - Service → **Settings** → **Volumes** → mount path **`/data`**
   - Size 10 GB+ (files live here: Mongo, uploads, secrets)
4. Settings → **Networking** → generate a domain.
5. Settings → **Variables** (optional but recommended):

   | Variable | Value |
   |---|---|
   | `DOMAIN` | your hostname only, e.g. `chat.example.com` |
   | `RAILWAY_RUN_UID` | `0` |

   If `DOMAIN` is unset, the image uses `RAILWAY_PUBLIC_DOMAIN`.
6. Attach a **custom domain** on the same service if you have one, and set `DOMAIN` to that hostname. Redeploy after DNS is live so the web client is injected with the right URL.
7. Open `https://<domain>`, register. That first account is your user.

First build pulls several GHCR images and can take 10–15 minutes.

## After deploy

- Secrets are stored on the volume at `/data/secrets.env`. **Back this file up.** Losing `REVOLT__FILES__ENCRYPTION_KEY` makes existing uploads unreadable.
- Logs: Railway deploy logs, or `supervisorctl status` via Railway SSH.
- Invite-only: SSH in, edit `/Revolt.toml` set `[api.registration] invite_only = true`, then `supervisorctl restart api`.
- Official desktop app (limited support):  
  `stoat-desktop --force-server=https://your.domain`

## Local test

```bash
docker build -t stoat-aio .
docker run --rm -p 8080:8080 -e PORT=8080 -e DOMAIN=localhost:8080 -v stoat-data:/data stoat-aio
```

HTTP only locally (`DOMAIN=localhost:8080` still writes `https://` URLs, so local browser use is awkward). Railway is the intended target.

## License

Upstream Stoat is AGPLv3. Modifications you run in production must be published. Do not use official Stoat brand assets to promote a third-party instance.
