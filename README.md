# Homelab

Notes and code from my home infrastructure. Running Unraid on a TerraMaster F6-424 Max, with a Docker stack for media, networking, automation, and a few personal projects. Maintained for fun and to avoid paying for services I can host myself.

---

## Hardware

| Component | Spec |
|---|---|
| **NAS** | TerraMaster F6-424 Max |
| **CPU** | Intel Core i5-1235U (12th gen, Alder Lake-P) |
| **GPU** | Intel Iris Xe (VA-API hardware transcoding for Plex) |
| **RAM** | 64 GB DDR4 |
| **Storage** | Targeting ~100 TB across 6 bays |
| **Boot** | 32 GB USB flash (Unraid) |
| **Network** | 2.5 GbE |

**Migration note:** Moved from a UGREEN DXP4800 after ongoing N100 hardware lockups made it unreliable as a 24/7 server. The TerraMaster has been stable.

---

## Docker Stack

Everything runs in Docker, managed through Unraid. All containers run on a custom bridge network (`medianet`) with static IPs.

| Category | Tools |
|---|---|
| **OS** | Unraid 7.x |
| **Media** | Plex, Sonarr, Radarr, Readarr, Bazarr |
| **Downloads** | qBittorrent (via Gluetun VPN), SABnzbd (Usenet), Prowlarr, cross-seed |
| **Requests** | Seerr (Overseerr fork) |
| **Automation** | Unpackarr, n8n |
| **Networking** | Gluetun (ProtonVPN WireGuard), Tailscale, AdGuard Home |
| **AI** | Gemini 2.5 Flash (primary), Claude (fallback/secondary) |

---

## Repository Structure

```
homelab/
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

A Discord bot I built to control the NAS from my phone. Accepts natural language — ask it to check stuck torrents, surface alerts, search for something, or tell you what's currently streaming. Built using **Gemini function calling** so Gemini decides which tools to invoke and writes all responses. Claude serves as a fallback.

**Capabilities:**
- Check download queue, speed, VPN status
- Search and manage Sonarr/Radarr/Readarr
- Plex library queries ("do I have X?", "what was recently added?", "what should I watch?")
- Trigger Bazarr subtitle searches
- Check active Plex streams
- Weekly Sunday digest of recently added content

**Tech:** Python 3, discord.py, Gemini 2.5 Flash function calling, Anthropic Claude API, no external dependencies beyond the AI SDKs.

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
# runs on a schedule; or trigger manually:
docker run --rm --env-file .env -v /var/run/docker.sock:/var/run/docker.sock nas-guardian python guardian.py --digest
```

---

### `readarr-server` — Local BookInfo Metadata API

A TypeScript/Bun server that provides Readarr's custom metadata source with book data from a local PostgreSQL database seeded from OpenLibrary. Eliminates dependency on external metadata APIs for ebook management.

```bash
cd apps/readarr-server
bun install
bun run src/index.ts
```

---

### `claude-bot` — Claude Discord Assistant

A minimal Discord bot backed by Claude for general Q&A and NAS assistance. Started as a quick experiment with the Anthropic API; the nas-bot grew out of this.

---

## Boot Scripts

These run on the Unraid host at startup (`/boot/config/scripts/`):

| Script | Purpose |
|---|---|
| `gluetun-watch.sh` | Polls Gluetun's forwarded port file; syncs to qBittorrent API on change |
| `vpn-health-check.sh` | Verifies VPN tunnel health after boot |
| `docker-ordered-start.sh` | Starts containers in dependency order (Gluetun first, then network-dependent containers) |
| `boot-crash-alert.sh` | Posts a Discord alert if the system rebooted unexpectedly |
| `backup-config.sh` | Tarballs `/boot/config` nightly to appdata |
| `sonarr-proxy.py` | Lightweight HTTP proxy giving SABnzbd access to Sonarr inside Gluetun's network namespace |
| `update-claude.sh` | Auto-updates the Claude Code CLI |

---

## Management Scripts

~90 PowerShell scripts for day-to-day operations. Highlights:

| Script | Purpose |
|---|---|
| `health-check.ps1` | Full stack health report |
| `check-queue.ps1` | Download queue status |
| `check-stalled.ps1` | Find and handle stalled downloads |
| `search-missing.ps1` | Trigger missing episode/movie searches |
| `cleanup-junk-files.ps1` | Remove sample files, extras, and garbage from media dirs |
| `find-untracked-media.ps1` | Find media files not tracked by Sonarr/Radarr |
| `reannounce-all.ps1` | Force-reannounce all torrents to trackers |
| `daily-status.ps1` | Posts a daily Discord status report |
| `monitor-containers.ps1` | Container health monitoring with Discord alerts |

---

## Design Choices

**VPN container wrap instead of host-level VPN** — Keeps the rest of the traffic outside the tunnel. qBittorrent and Prowlarr run inside Gluetun's network namespace via `--net=container:Gluetun`. Plex, SABnzbd, and bots run normally. Prevents the VPN from throttling streams or interfering with Usenet.

**Symlinks for cross-seed** — Unraid's shfs spans multiple physical disks, so hardlinks fail across mounts. cross-seed uses symlinks into a dedicated `/data/cross-seeds` directory outside the main data dirs.

**Gemini function calling over prompt engineering** — The nas-bot uses Gemini's native function calling rather than prompt-engineered tool use, which gives more reliable tool selection and cleaner response generation.

**Unraid over TrueNAS** — Flexibility of mixed-size drives matters more than ZFS features for my use case.

**Plex and Jellyfin both running** — Plex for the family (no retraining needed), Jellyfin for personal use and as an open-source hedge.

---

## What I'd Do Differently

Debugged the UGREEN N100 lockups too long before migrating. If you're seeing recurring hardware lockups on an N100-class NAS, don't chase them — switch platforms.

Started on the Unraid trial and purchased the Unleashed license; would probably have gone straight to Lifetime knowing how long I've been at this.

---

## License

MIT
