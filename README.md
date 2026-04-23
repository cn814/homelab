# Homelab NAS — Infrastructure & Automation

A self-hosted media server and home automation platform built on [Unraid](https://unraid.net/), running on a **TerraMaster F6-424 Max** (Intel Core i5-1235U, 64 GB RAM, 6-bay NAS). This repo contains all the custom automation code, Docker configuration, and management scripts that run the stack.

---

## Stack Overview

| Category | Tools |
|---|---|
| **OS** | Unraid 7.x |
| **Media** | Plex, Sonarr, Radarr, Readarr, Bazarr |
| **Downloads** | qBittorrent (via Gluetun VPN), SABnzbd (Usenet), Prowlarr, cross-seed |
| **Requests** | Seerr (Overseerr fork) |
| **Automation** | Unpackarr, n8n |
| **Networking** | Gluetun (ProtonVPN WireGuard), Tailscale, AdGuard Home |
| **AI** | Gemini 2.5 Flash (primary), Claude (fallback/secondary) |

All containers run on a custom Docker bridge network (`medianet`) with static IPs. qBittorrent and the \*arr stack share Gluetun's network namespace for VPN-routed traffic.

---

## Repository Structure

```
homelab-nas/
├── apps/
│   ├── nas-bot/          # Discord bot — natural language NAS control
│   ├── guardian/         # Twice-daily health digest + auto-remediation
│   ├── claude-bot/       # Claude-powered Discord assistant
│   └── readarr-server/   # Local BookInfo metadata API (TypeScript/Bun)
├── boot-scripts/         # Unraid startup scripts (/boot/config/scripts/)
├── management-scripts/   # PowerShell utility scripts for the media stack
└── compose/              # Docker Compose configuration
```

---

## Apps

### `nas-bot` — AI-Powered Discord Bot

A Discord bot that lets you control the entire NAS with natural language. Built using **Gemini function calling** — Gemini decides which tools to invoke and generates all responses. Claude serves as a fallback.

**Capabilities:**
- Check download queue, speed, VPN status
- Search and manage Sonarr/Radarr/Readarr
- Plex library queries ("do I have X?", "what was recently added?", "what should I watch?")
- Trigger Bazarr subtitle searches
- Check active Plex streams
- Weekly Sunday digest of recently added content

**Tech:** Python 3, discord.py, Gemini 2.5 Flash function calling, Anthropic Claude API, zero external dependencies beyond the AI SDKs.

```bash
cd apps/nas-bot
cp .env.example .env  # fill in your keys
docker build -t nas-bot .
docker run -d --name nas-bot --env-file .env nas-bot
```

---

### `guardian` — Automated Health Monitor

Runs at **8 AM and 8 PM** via cron. Performs auto-remediation first, then posts a Gemini-written plain-English summary to a Discord `#nas-digest` channel.

**Auto-fixes (no human required):**
- Restart stopped/exited containers
- Sync VPN forwarded port to qBittorrent when it changes
- Delete dead torrents (metaDL/stalledDL with 0 seeds)
- Reset \*arr indexer circuit breakers + trigger RSS sync
- Fix Unpackarr container IP drift after network recreation
- Delete SABnzbd jobs with >50% missing articles + trigger re-search
- Clear stuck import-failed queue items in Sonarr/Radarr (>2h)
- Clear stale completed Readarr queue items
- Fix stale Seerr hostnames after IP changes
- Docker dangling image prune
- Weekly orphaned incomplete directory cleanup (Sundays)

**Alerts (report only):** Bazarr missing subtitles, qBittorrent firewalled, log files >100 MB, HDD SMART failures, disk usage >90%, CPU temp >85°C.

```bash
cd apps/guardian
cp .env.example .env
docker build -t nas-guardian .
# runs on a schedule; or manually:
docker run --rm --env-file .env -v /var/run/docker.sock:/var/run/docker.sock nas-guardian python guardian.py --digest
```

---

### `readarr-server` — Local BookInfo Metadata API

A TypeScript/Bun server that provides Readarr's custom metadata source with book data from a local PostgreSQL database (seeded from OpenLibrary). Eliminates dependency on external metadata APIs for ebook management.

```bash
cd apps/readarr-server
bun install
bun run src/index.ts
```

---

### `claude-bot` — Claude Discord Assistant

A minimal Discord bot backed by Claude claude-sonnet-4-6 for general Q&A and NAS assistance. Reads secrets from environment variables.

---

## Boot Scripts

Located in `boot-scripts/` — these run on the Unraid host at startup:

| Script | Purpose |
|---|---|
| `gluetun-watch.sh` | Polls Gluetun's forwarded port file; syncs to qBittorrent API on change |
| `vpn-health-check.sh` | Verifies VPN tunnel health after boot |
| `docker-ordered-start.sh` | Starts containers in dependency order (Gluetun first, then network-dependent containers) |
| `boot-crash-alert.sh` | Posts a Discord alert if the system rebooted unexpectedly |
| `backup-config.sh` | Tarballs `/boot/config` nightly to appdata |
| `sonarr-proxy.py` | Lightweight HTTP proxy giving SABnzbd access to Sonarr inside Gluetun's netns |
| `nas-bot.py` | Runs the NAS bot directly on host (alternative to containerized version) |
| `update-claude.sh` | Auto-updates the Claude Code CLI |

---

## Management Scripts

`management-scripts/` contains ~90 PowerShell scripts for day-to-day operations. Highlights:

| Script | Purpose |
|---|---|
| `health-check.ps1` | Full stack health report |
| `check-queue.ps1` | Download queue status |
| `check-stalled.ps1` | Find and handle stalled downloads |
| `search-missing.ps1` | Trigger missing episode/movie searches |
| `cleanup-junk-files.ps1` | Remove sample files, extras, and garbage from media dirs |
| `find-untracked-media.ps1` | Find media files not tracked by Sonarr/Radarr |
| `reannounce-all.ps1` | Force-reannounce all torrents to trackers |
| `sync-qbittorrent-port.ps1` | Manual VPN port sync |
| `daily-status.ps1` | Posts a daily Discord status report |
| `monitor-containers.ps1` | Container health monitoring with Discord alerts |

Scripts use `$env:QBIT_USER` / `$env:QBIT_PASS` for qBittorrent credentials.

---

## Key Design Decisions

**VPN network namespace sharing** — Rather than routing all traffic through the VPN, only qBittorrent and the \*arr indexer traffic (Prowlarr) run inside Gluetun's network namespace via `--net=container:Gluetun`. Plex, SABnzbd, and bots run normally. This prevents the VPN from throttling Plex streams or interfering with Usenet.

**Symlinks for cross-seed** — Unraid's shfs spans multiple physical disks, so hardlinks fail across mounts. cross-seed uses symlinks (`linkType: "symlink"`) into a dedicated `/data/cross-seeds` directory outside the main data dirs.

**No mock dependencies** — The guardian and nas-bot communicate directly with live service APIs. Health checks test real endpoints rather than mocked state.

**Gemini function calling over prompt engineering** — The nas-bot uses Gemini's native function calling rather than prompt-engineered tool use, which gives more reliable tool selection and cleaner response generation.

---

## Hardware

| Component | Spec |
|---|---|
| **NAS** | TerraMaster F6-424 Max |
| **CPU** | Intel Core i5-1235U (12th gen, Alder Lake-P) |
| **GPU** | Intel Iris Xe (VA-API hardware transcoding for Plex) |
| **RAM** | 64 GB DDR4 |
| **Boot** | 32 GB USB flash (Unraid) |
| **Network** | 2.5 GbE |

---

## License

MIT
