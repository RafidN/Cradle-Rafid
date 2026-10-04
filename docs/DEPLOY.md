# Deploying

How to put the game on the internet. Early Access runs on **one Linux machine**: a VPS with 4 vCPU and 8 GB RAM is plenty, for about $10–40 a month from Hetzner, DigitalOcean, Vultr, OVH and similar. Everything runs in Docker.

## What runs where

| Container | Purpose | Port |
|---|---|---|
| `postgres` | Accounts, characters and saves | internal only |
| `backend` | Login, characters, join tickets, saving | 8080/tcp, or 443 via Caddy |
| `zone-proving-grounds` | Game server for the Proving Grounds | 7777/udp |
| `zone-ember-wilds` | Game server for Ember Wilds | 7778/udp |
| `backup` | Nightly `pg_dump` to `deploy/backups/`, keeping 14 days | — |
| `caddy` (optional) | HTTPS for the backend at your domain | 80, 443 |

## 1. Publish images

CI builds and tests every push. It **publishes** the server and backend images to GitHub's container registry only when you push a version tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Wait for the CI run to go green (GitHub → Actions). The images appear at `ghcr.io/<you>/cradle-server` and `ghcr.io/<you>/cradle-backend`.

The first time, set both packages to **public** (GitHub → your profile → Packages → package settings), or log the server in with `docker login ghcr.io`.

## 2. Prepare the machine

On a fresh Ubuntu or Debian VPS:

```bash
curl -fsSL https://get.docker.com | sh
git clone https://github.com/RafidN/Cradle-Rafid.git && cd Cradle-Rafid/deploy
cp .env.example .env && nano .env
```

Fill in `.env`:
- `POSTGRES_PASSWORD` and `SERVER_SECRET`: long random strings. Generate them with `openssl rand -hex 32`.
- `PUBLIC_HOST`: the machine's public IP or hostname. Game clients connect to it.
- `DOMAIN`: a domain whose DNS points at the machine (for HTTPS).
- `VERSION`: the tag you published, for example `v0.1.0`.

Open the firewall for **UDP 7777–7778**, plus **TCP 80 and 443** for HTTPS (or **TCP 8080** without HTTPS).

## 3. Start it

```bash
docker compose --profile https up -d     # with HTTPS (recommended)
docker compose up -d                     # without HTTPS: backend on http://<host>:8080
```

Check the backend:

```bash
curl https://<domain>/health    # → {"ok":true}
curl https://<domain>/shards    # → both zones listed
```

## 4. Point a client at it

In Godot, set **Project Settings → Game → Backend URL** (`game/backend_url`) to `https://<domain>`, then export the Windows client. CI also exports one, but with the default URL. Players can also edit the URL field on the login screen.

## Updating

```bash
# after tagging and publishing a new version:
nano .env                       # VERSION=v0.1.1
docker compose pull && docker compose up -d
```

Stopping a game server (`docker compose stop`, `up -d` with a new image, or a reboot) sends it SIGTERM. The entrypoint turns that into a graceful shutdown: players are warned and saved first. `stop_grace_period` allows 30 seconds for this.

## Operations

- **Server status:**
  ```bash
  docker compose exec zone-proving-grounds bash -c 'exec 3<>/dev/tcp/127.0.0.1/8777; echo status >&3; head -1 <&3'
  ```
- **Restart with a reason** (players see the shutdown notice):
  ```bash
  docker compose restart zone-ember-wilds
  ```
- **Logs:**
  ```bash
  docker compose logs -f zone-ember-wilds
  ```
- **Restore a backup:**
  ```bash
  docker compose exec -T postgres pg_restore -U cradle -d cradle --clean < backups/cradle-YYYY-MM-DD.dump
  ```
  **Test a restore before you need one.**
- **Off-site backups:** copy `deploy/backups/` somewhere else on a schedule (rclone to S3 or B2, or your provider's snapshots). A backup on the same disk doesn't survive losing the disk.

## Not done yet (before strangers play: roadmap Phase 8)

- Monitoring and alerts
- A status page
- Rate limiting on login
- Moderation tools
- Steam login, which replaces username and password
