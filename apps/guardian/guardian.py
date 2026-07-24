"""
nas-guardian — twice-daily NAS health digest with auto-remediation
Runs at 8 AM and 8 PM, fixes what it can, posts a Gemini summary to #nas-digest.

Auto-fixes:
  - Restart stopped/exited monitored containers
  - Sync VPN port from Gluetun → qBittorrent if mismatched
  - Delete dead torrents (metaDL/stalledDL with 0 seeds)
  - Reset Sonarr/Radarr indexer circuit breakers when tripped
  - Fix Unpackarr IP drift after container recreation
  - Delete SABnzbd jobs with >50% missing articles + trigger re-search
  - Clear Sonarr/Radarr stuck import-failed queue items (>2h)
  - Clear Readarr stale completed queue items (duplicates/not-upgrades, >1h)
  - Fix stale Seerr Sonarr/Radarr URLs after IP change
  - Docker dangling image prune
  - Weekly orphaned incomplete directory cleanup (Sundays)

Alerts (report only):
  - Bazarr missing subtitle counts
  - qBittorrent firewalled status
  - Log files exceeding 100 MB
  - HDD SMART failures
  - Disk usage > 90%
  - CPU temp > 85°C
"""

import json
import os
import re
import shutil
import socket
import subprocess
import urllib.request
import urllib.parse
import http.cookiejar
import time
from datetime import datetime, timezone

# ── Config ────────────────────────────────────────────────────────────────────

DISCORD_BOT_TOKEN  = os.environ["DISCORD_BOT_TOKEN"]
DIGEST_CHANNEL_ID  = os.environ["DIGEST_CHANNEL_ID"]

SONARR_URL   = "http://localhost:8989"
SONARR_KEY   = os.environ["SONARR_KEY"]
RADARR_URL   = "http://localhost:7878"
RADARR_KEY   = os.environ["RADARR_KEY"]
QBIT_URL     = "http://localhost:8090"
QBIT_USER    = os.environ.get("QBIT_USER", "admin")
QBIT_PASS    = os.environ["QBIT_PASS"]
PROWLARR_URL = "http://localhost:9696"
SABNZBD_KEY  = os.environ["SABNZBD_KEY"]
BAZARR_URL   = "http://localhost:6767"
BAZARR_KEY   = os.environ["BAZARR_KEY"]
SEERR_SETTINGS = "/mnt/cache/appdata/seerr/settings.json"
INCOMPLETE_DIR = "/mnt/user/data/usenet/incomplete"
UNPACKARR_XML  = "/boot/config/plugins/dockerMan/templates-user/my-unpackarr.xml"

READARR_URL  = "http://localhost:8787"
READARR_KEY  = os.environ["READARR_KEY"]

ANTHROPIC_API_KEY = os.environ["ANTHROPIC_API_KEY"]
ANTHROPIC_MODEL   = "claude-haiku-4-5"

DISK_WARN_PCT  = 90
MISSING_THRESHOLD = 0.50   # delete SABnzbd job if >50% of articles are missing
STUCK_QUEUE_SECS  = 7200   # 2 hours

EXPECTED_CONTAINERS = [
    "Gluetun", "sonarr", "radarr", "qbittorrent", "prowlarr",
    "plex", "bazarr", "cross-seed", "unpackarr", "seer",
    "nas-bot", "flaresolverr", "sabnzbd",
    "nas-guardian", "sdat-monitor", "usgovernment",
]
RESTARTABLE_CONTAINERS = [
    "sonarr", "radarr", "qbittorrent", "prowlarr",
    "plex", "bazarr", "cross-seed", "unpackarr", "seer",
    "nas-bot", "flaresolverr", "sabnzbd", "sdat-monitor", "usgovernment",
]
LOG_FILES = [
    ("/mnt/user/appdata/n8n/nas-bot.log", "nas-bot"),
    ("/var/log/nas-guardian.log",          "nas-guardian"),
]

# ── HTTP helpers ──────────────────────────────────────────────────────────────

def http_get(url, headers=None):
    req = urllib.request.Request(url, headers=headers or {})
    return json.loads(urllib.request.urlopen(req, timeout=15).read())

def http_post(url, data, headers=None):
    body = json.dumps(data).encode()
    h = {"Content-Type": "application/json", **(headers or {})}
    req = urllib.request.Request(url, data=body, headers=h, method="POST")
    return json.loads(urllib.request.urlopen(req, timeout=30).read())

def http_delete(url, headers=None):
    req = urllib.request.Request(url, headers=headers or {}, method="DELETE")
    urllib.request.urlopen(req, timeout=15)

def arr_get(base, key, path):
    return http_get(f"{base}/api/v3/{path}", {"X-Api-Key": key})

def arr_post(base, key, path, data):
    return http_post(f"{base}/api/v3/{path}", data, {"X-Api-Key": key})

def arr_delete(base, key, path):
    http_delete(f"{base}/api/v3/{path}", {"X-Api-Key": key})

def qbit_session():
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    data = urllib.parse.urlencode({"username": QBIT_USER, "password": QBIT_PASS}).encode()
    opener.open(f"{QBIT_URL}/api/v2/auth/login", data, timeout=10)
    return opener

def qbit_get(opener, path):
    return json.loads(opener.open(f"{QBIT_URL}/api/v2/{path}", timeout=15).read())

def qbit_post(opener, path, params):
    data = urllib.parse.urlencode(params).encode()
    opener.open(f"{QBIT_URL}/api/v2/{path}", data, timeout=15)

def _prowlarr_key():
    try:
        import xml.etree.ElementTree as ET
        tree = ET.parse("/mnt/user/appdata/prowlarr/config.xml")
        return tree.getroot().findtext("ApiKey", "")
    except Exception:
        return ""

def _docker_inspect(name):
    r = subprocess.run(["docker", "inspect", name], capture_output=True, text=True)
    return json.loads(r.stdout)[0] if r.returncode == 0 else None

def _medianet_ip(name):
    data = _docker_inspect(name)
    if not data:
        return None
    return data["NetworkSettings"]["Networks"].get("medianet", {}).get("IPAddress")

def _host_lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return None

# ── Auto-fix: containers ──────────────────────────────────────────────────────

def fix_containers():
    actions = []
    r = subprocess.run(["docker", "ps", "--format", "{{.Names}}"], capture_output=True, text=True)
    running = set(r.stdout.strip().splitlines())
    for name in RESTARTABLE_CONTAINERS:
        if name not in running:
            data = _docker_inspect(name)
            if data is None:
                actions.append(f"⚠️ {name} not found (needs manual recreation)")
                continue
            status = data["State"]["Status"]
            r2 = subprocess.run(["docker", "start", name], capture_output=True, text=True)
            if r2.returncode == 0:
                actions.append(f"🔄 Restarted {name} (was {status})")
            else:
                actions.append(f"❌ Failed to restart {name}: {r2.stderr.strip()[:80]}")
    return actions

# ── Auto-fix: VPN port sync ───────────────────────────────────────────────────

def fix_vpn_port():
    try:
        gluetun_port = subprocess.run(
            ["docker", "exec", "Gluetun", "cat", "/tmp/gluetun/forwarded_port"],
            capture_output=True, text=True).stdout.strip()
        if not gluetun_port.isdigit():
            return None
        opener = qbit_session()
        prefs = qbit_get(opener, "app/preferences")
        if str(prefs.get("listen_port", "")) != gluetun_port:
            qbit_post(opener, "app/setPreferences",
                      {"json": json.dumps({"listen_port": int(gluetun_port)})})
            return f"🔌 VPN port synced → {gluetun_port}"
    except Exception as e:
        return f"⚠️ VPN port sync failed: {e}"
    return None

# ── Auto-fix: dead torrents ───────────────────────────────────────────────────

def fix_dead_torrents():
    try:
        opener = qbit_session()
        torrents = qbit_get(opener, "torrents/info")
        dead = [t for t in torrents
                if t.get("state") in ("metaDL", "stalledDL")
                and (t.get("num_seeds", 0) + t.get("num_complete", 0)) == 0]
        if not dead:
            return None
        qbit_post(opener, "torrents/delete",
                  {"hashes": "|".join(t["hash"] for t in dead), "deleteFiles": "true"})
        return (f"🗑️ Deleted {len(dead)} dead torrent(s): "
                f"{', '.join(t['name'][:35] for t in dead[:3])}")
    except Exception as e:
        return f"⚠️ Dead torrent cleanup failed: {e}"

# ── Auto-fix: indexer circuit breakers ───────────────────────────────────────

def fix_indexer_circuit_breakers():
    actions = []
    for name, base, key in [("Sonarr", SONARR_URL, SONARR_KEY),
                              ("Radarr", RADARR_URL, RADARR_KEY)]:
        try:
            disabled = arr_get(base, key, "indexerstatus")
            if disabled:
                arr_delete(base, key, "indexerstatus")
                arr_post(base, key, "command", {"name": "RssSync"})
                actions.append(f"{name} ({len(disabled)})")
        except Exception:
            pass
    return f"🔁 Reset circuit breakers: {', '.join(actions)}" if actions else None

# ── Auto-fix: Unpackarr IP drift ──────────────────────────────────────────────

def fix_unpackarr():
    try:
        radarr_ip  = _medianet_ip("radarr")
        gluetun_ip = _medianet_ip("Gluetun")
        if not radarr_ip or not gluetun_ip:
            return None
        correct_radarr = f"http://{radarr_ip}:7878"
        correct_sonarr = f"http://{gluetun_ip}:8989"
        data = _docker_inspect("unpackarr")
        if not data:
            return None
        env = dict(e.partition("=")[::2] for e in data["Config"]["Env"])
        if env.get("UN_RADARR_0_URL") == correct_radarr and env.get("UN_SONARR_0_URL") == correct_sonarr:
            return None
        changes = []
        if env.get("UN_RADARR_0_URL") != correct_radarr:
            changes.append(f"Radarr → {correct_radarr}")
        if env.get("UN_SONARR_0_URL") != correct_sonarr:
            changes.append(f"Sonarr → {correct_sonarr}")
        try:
            with open(UNPACKARR_XML) as f:
                xml = f.read()
            xml = re.sub(r'172\.17\.0\.\d+:7878', f'{radarr_ip}:7878', xml)
            xml = re.sub(r'172\.17\.0\.\d+:8989', f'{gluetun_ip}:8989', xml)
            with open(UNPACKARR_XML, "w") as f:
                f.write(xml)
        except Exception:
            pass
        image   = data["Config"]["Image"]
        binds   = data["HostConfig"].get("Binds") or []
        restart = data["HostConfig"]["RestartPolicy"]["Name"]
        env["UN_RADARR_0_URL"] = correct_radarr
        env["UN_SONARR_0_URL"] = correct_sonarr
        env_args = [a for k, v in env.items() if k != "PATH" for a in ("-e", f"{k}={v}")]
        vol_args = [a for b in binds for a in ("-v", b)]
        subprocess.run(["docker", "stop", "unpackarr"], capture_output=True)
        subprocess.run(["docker", "rm",   "unpackarr"], capture_output=True)
        r = subprocess.run(
            ["docker", "run", "-d", "--name", "unpackarr", f"--restart={restart}",
             "--network", "medianet"]
            + vol_args + env_args + [image], capture_output=True, text=True)
        return (f"🔧 Fixed Unpackarr IP drift: {'; '.join(changes)}"
                if r.returncode == 0
                else f"⚠️ Unpackarr IP fix failed: {r.stderr.strip()[:80]}")
    except Exception as e:
        return f"⚠️ Unpackarr check failed: {e}"

# ── Auto-fix: SABnzbd high-missing jobs ──────────────────────────────────────

def fix_sabnzbd_high_missing():
    try:
        q = http_get(f"http://localhost:8080/api?apikey={SABNZBD_KEY}"
                     f"&mode=queue&output=json&limit=500")
        slots = q.get("queue", {}).get("slots", [])
        removed = []
        for s in slots:
            mb      = float(s.get("mb", 0))
            missing = float(s.get("mbmissing", 0))
            if mb > 50 and missing / mb > MISSING_THRESHOLD:
                nzo = s["nzo_id"]
                http_get(f"http://localhost:8080/api?apikey={SABNZBD_KEY}"
                         f"&mode=queue&name=delete&value={nzo}&del_files=1&output=json")
                removed.append(f"{s['filename'][:40]} ({missing/mb*100:.0f}% missing)")
        if not removed:
            return None
        # Trigger re-searches
        for base, key, cmd in [(SONARR_URL, SONARR_KEY, "MissingEpisodeSearch"),
                                (RADARR_URL, RADARR_KEY, "MissingMoviesSearch")]:
            try:
                arr_post(base, key, "command", {"name": cmd})
            except Exception:
                pass
        return (f"🗑️ Removed {len(removed)} high-missing SABnzbd job(s) + triggered re-search: "
                f"{'; '.join(removed[:3])}")
    except Exception as e:
        return f"⚠️ SABnzbd missing-article check failed: {e}"

# ── Auto-fix: Sonarr/Radarr stuck import queue ───────────────────────────────

def fix_stuck_arr_queue():
    actions = []
    now = datetime.now()
    for name, base, key in [("Sonarr", SONARR_URL, SONARR_KEY),
                              ("Radarr", RADARR_URL, RADARR_KEY)]:
        try:
            queue = arr_get(base, key, "queue?page=1&pageSize=200&includeUnknownMovieItems=true")
            records = queue.get("records", []) if isinstance(queue, dict) else []
            for item in records:
                dl_status = item.get("trackedDownloadStatus", "ok")
                dl_state  = item.get("trackedDownloadState", "")
                if dl_status not in ("warning", "error"):
                    continue
                if dl_state not in ("importFailed", "importBlocked", "failedPending", "failed"):
                    continue
                added = item.get("added", "")
                if not added:
                    continue
                added_dt = datetime.fromisoformat(added.replace("Z", "")).replace(tzinfo=None)
                if (now - added_dt).total_seconds() < STUCK_QUEUE_SECS:
                    continue
                try:
                    arr_delete(base, key,
                               f"queue/{item['id']}?blocklist=true&removeFromClient=false")
                    actions.append(f"{name}: {item.get('title', '?')[:40]}")
                except Exception:
                    pass
        except Exception:
            pass
    return f"🔁 Cleared stuck queue items: {', '.join(actions)}" if actions else None

# ── Auto-fix: Readarr stale completed queue items ─────────────────────────────

def fix_readarr_completed_queue():
    try:
        url = (f"{READARR_URL}/api/v1/queue"
               f"?pageSize=500&includeUnknownAuthorItems=true")
        queue = http_get(url, {"X-Api-Key": READARR_KEY})
        records = queue.get("records", []) if isinstance(queue, dict) else []
        now = datetime.now(timezone.utc)
        stale = []
        for item in records:
            if item.get("status") != "completed":
                continue
            added = item.get("added", "")
            if added:
                added_dt = datetime.fromisoformat(added.replace("Z", "+00:00"))
                if (now - added_dt).total_seconds() < 3600:
                    continue
            stale.append(item["id"])
        if not stale:
            return None
        body = json.dumps({"ids": stale}).encode()
        req = urllib.request.Request(
            f"{READARR_URL}/api/v1/queue/bulk"
            f"?removeFromClient=false&blocklist=false",
            data=body,
            headers={"X-Api-Key": READARR_KEY, "Content-Type": "application/json"},
            method="DELETE",
        )
        urllib.request.urlopen(req, timeout=15)
        return f"🗑️ Cleared {len(stale)} stale Readarr completed queue item(s)"
    except Exception as e:
        return f"⚠️ Readarr queue cleanup failed: {e}"

# ── Auto-fix: Seerr stale URLs ────────────────────────────────────────────────

def fix_seerr_urls():
    try:
        current_ip = _host_lan_ip()
        if not current_ip:
            return None
        with open(SEERR_SETTINGS) as f:
            settings = json.load(f)
        changed = []
        for arr in settings.get("radarr", []) + settings.get("sonarr", []):
            if arr.get("hostname") != current_ip:
                changed.append(f"{arr.get('name','?')}: {arr['hostname']} → {current_ip}")
                arr["hostname"] = current_ip
        if not changed:
            return None
        with open(SEERR_SETTINGS, "w") as f:
            json.dump(settings, f, indent=2)
        subprocess.run(["docker", "restart", "seer"], capture_output=True)
        return f"🔧 Fixed Seerr URLs ({', '.join(changed)})"
    except Exception as e:
        return f"⚠️ Seerr URL check failed: {e}"

# ── Auto-fix: Docker image prune ─────────────────────────────────────────────

def fix_docker_images():
    try:
        r = subprocess.run(["docker", "image", "prune", "-f"],
                           capture_output=True, text=True)
        m = re.search(r"Total reclaimed space: (.+)", r.stdout)
        space = m.group(1) if m else ""
        if not space or space == "0B":
            return None
        return f"🧹 Docker image prune freed {space}"
    except Exception as e:
        return f"⚠️ Docker prune failed: {e}"

# ── Auto-fix: Orphaned incomplete directories (Sundays only) ─────────────────

def fix_orphaned_incomplete():
    if datetime.now().weekday() != 6:   # 0=Mon … 6=Sun
        return None
    try:
        q = http_get(f"http://localhost:8080/api?apikey={SABNZBD_KEY}"
                     f"&mode=queue&output=json&limit=1000")
        active_ids = {s["nzo_id"] for s in q.get("queue", {}).get("slots", [])}
        orphaned = []
        for dirname in os.listdir(INCOMPLETE_DIR):
            dirpath = os.path.join(INCOMPLETE_DIR, dirname)
            if not os.path.isdir(dirpath):
                continue
            admin = os.path.join(dirpath, "__ADMIN__")
            if not os.path.isdir(admin):
                continue
            nzo_files = [f for f in os.listdir(admin) if f.startswith("SABnzbd_nzo_")]
            if not nzo_files or nzo_files[0] not in active_ids:
                orphaned.append(dirpath)
        if not orphaned:
            return None
        for d in orphaned:
            shutil.rmtree(d, ignore_errors=True)
        return f"🧹 Weekly cleanup: removed {len(orphaned)} orphaned incomplete directories"
    except Exception as e:
        return f"⚠️ Orphan cleanup failed: {e}"

# ── Health checks (read-only) ─────────────────────────────────────────────────

def check_all():
    result = {}
    issues = []

    # Uptime / load
    try:
        upt = subprocess.run(["uptime"], capture_output=True, text=True).stdout.strip()
        result["uptime"] = upt
        load = float(upt.split("load average:")[1].split(",")[0].strip())
        if load > 8:
            issues.append(f"High load: {load:.1f}")
    except Exception as e:
        result["uptime_error"] = str(e)

    # Memory
    try:
        mem = subprocess.run(["free", "-h"], capture_output=True, text=True).stdout
        for line in mem.splitlines():
            if line.startswith("Mem:"):
                p = line.split()
                result["memory"] = {"total": p[1], "used": p[2], "available": p[6]}
            elif line.startswith("Swap:"):
                p = line.split()
                result["swap"] = {"total": p[1], "used": p[2]}
    except Exception:
        pass

    # CPU temp
    try:
        sensors = subprocess.run(["sensors"], capture_output=True, text=True).stdout
        for line in sensors.splitlines():
            if "Package id 0" in line:
                m = re.search(r'\+(\d+\.\d+)°C', line)
                if m:
                    t = float(m.group(1))
                    result["cpu_temp_c"] = t
                    if t > 85:
                        issues.append(f"CPU temp high: {t}°C")
                break
    except Exception:
        pass

    # Disk usage
    try:
        df = subprocess.run(["df", "-h", "/mnt/user", "/mnt/cache", "/boot"],
                            capture_output=True, text=True).stdout
        disks = []
        for line in df.splitlines()[1:]:
            p = line.split()
            if len(p) >= 6:
                pct = int(p[4].rstrip("%"))
                if pct >= DISK_WARN_PCT:
                    issues.append(f"Disk {p[5]} is {p[4]} full")
                disks.append({"mount": p[5], "size": p[1], "used": p[2],
                               "avail": p[3], "use_pct": p[4]})
        result["disk_usage"] = disks
    except Exception:
        pass

    # Containers (post-restart)
    try:
        r = subprocess.run(["docker", "ps", "--format", "{{.Names}}"],
                           capture_output=True, text=True)
        running = set(r.stdout.strip().splitlines())
        down = [c for c in EXPECTED_CONTAINERS if c not in running]
        if down:
            issues.append(f"Still down: {', '.join(down)}")
        result["containers"] = {"running": len(running), "down": down}
    except Exception:
        pass

    # VPN / qBittorrent (post-port-sync)
    try:
        opener = qbit_session()
        transfer = qbit_get(opener, "transfer/info")
        conn = transfer.get("connection_status", "?")
        if conn == "firewalled":
            issues.append("qBittorrent firewalled — VPN connected but port not open")
        elif conn != "connected":
            issues.append(f"VPN not connected: {conn}")
        gluetun_port = subprocess.run(
            ["docker", "exec", "Gluetun", "cat", "/tmp/gluetun/forwarded_port"],
            capture_output=True, text=True).stdout.strip()
        result["vpn"] = {
            "connection": conn,
            "port": gluetun_port,
            "dl_mbps": round(transfer.get("dl_info_speed", 0) / 1e6, 2),
            "ul_mbps": round(transfer.get("up_info_speed", 0) / 1e6, 2),
        }
    except Exception as e:
        result["vpn_error"] = str(e)

    # qBittorrent error-state torrents (post-cleanup)
    try:
        opener = qbit_session()
        torrents = qbit_get(opener, "torrents/info")
        errors = [t["name"][:50] for t in torrents if t.get("state") == "error"]
        if errors:
            issues.append(f"{len(errors)} torrent(s) in error state")
        result["qbit"] = {
            "total": len(torrents),
            "error_count": len(errors),
            "errors": errors[:3],
        }
    except Exception as e:
        result["qbit_error"] = str(e)

    # SABnzbd
    try:
        q = http_get(f"http://localhost:8080/api?apikey={SABNZBD_KEY}"
                     f"&mode=queue&output=json&limit=1")
        queue = q.get("queue", {})
        result["sabnzbd"] = {
            "status": queue.get("status"),
            "jobs": int(queue.get("noofslots", 0)),
            "speed": queue.get("speed"),
            "size_left": queue.get("sizeleft"),
        }
    except Exception:
        pass

    # Sonarr health
    try:
        health = arr_get(SONARR_URL, SONARR_KEY, "health")
        warns = [h["message"] for h in health if h["type"] in ("error", "warning")]
        for w in warns:
            issues.append(f"Sonarr: {w[:80]}")
        result["sonarr_health"] = warns
    except Exception:
        pass

    # Radarr health
    try:
        health = arr_get(RADARR_URL, RADARR_KEY, "health")
        warns = [h["message"] for h in health if h["type"] in ("error", "warning")]
        for w in warns:
            issues.append(f"Radarr: {w[:80]}")
        result["radarr_health"] = warns
    except Exception:
        pass

    # Bazarr missing subtitles (alert only)
    try:
        ep    = http_get(f"{BAZARR_URL}/api/episodes/wanted?start=0&length=1",
                         {"X-API-KEY": BAZARR_KEY})
        movie = http_get(f"{BAZARR_URL}/api/movies/wanted?start=0&length=1",
                         {"X-API-KEY": BAZARR_KEY})
        result["bazarr"] = {
            "episodes_missing": ep.get("total", 0),
            "movies_missing": movie.get("total", 0),
        }
    except Exception:
        pass

    # HDD SMART (alert only)
    smart_issues = []
    for dev in ("/dev/sdb", "/dev/sdc", "/dev/sdd", "/dev/sde",
                "/dev/sdf", "/dev/sdg", "/dev/sdh"):
        try:
            r = subprocess.run(["smartctl", "-H", dev], capture_output=True, text=True)
            if r.returncode in (0, 4) and "FAILED" in r.stdout:
                smart_issues.append(f"{dev} SMART FAILED")
        except Exception:
            pass
    if smart_issues:
        issues.extend(smart_issues)
    result["smart_issues"] = smart_issues

    # Log file sizes (alert only)
    log_issues = []
    for path, name in LOG_FILES:
        try:
            size_mb = os.path.getsize(path) // 1024 // 1024
            if size_mb > 100:
                log_issues.append(f"{name} log is {size_mb} MB")
        except Exception:
            pass
    if log_issues:
        issues.extend(log_issues)
    result["log_issues"] = log_issues

    result["issues"] = issues
    return result

# ── Gemini summary ────────────────────────────────────────────────────────────

def ai_summarise(findings, actions_taken):
    vpn   = findings.get("vpn", {})
    qbit  = findings.get("qbit", {})
    sab   = findings.get("sabnzbd", {})
    mem   = findings.get("memory", {})
    disk  = findings.get("disk_usage", [])
    cpu_t = findings.get("cpu_temp_c")
    conts = findings.get("containers", {})
    baz   = findings.get("bazarr", {})
    issues = findings.get("issues", [])

    ctx = [f"Time: {datetime.now().strftime('%I:%M %p')}"]
    if cpu_t:
        ctx.append(f"CPU: {cpu_t}°C")
    if mem:
        ctx.append(f"RAM: {mem.get('used')}/{mem.get('total')}")
    for d in disk:
        ctx.append(f"Disk {d['mount']}: {d['use_pct']} ({d['avail']} free)")
    if conts:
        down = conts.get("down", [])
        ctx.append(f"Containers: {conts.get('running')} up"
                   + (f", still down: {down}" if down else ""))
    if vpn:
        ctx.append(f"VPN: {vpn.get('connection')}, "
                   f"dl={vpn.get('dl_mbps')} MB/s ul={vpn.get('ul_mbps')} MB/s")
    if qbit:
        ctx.append(f"Torrents: {qbit.get('total')} total, "
                   f"{qbit.get('error_count')} errors")
    if sab:
        ctx.append(f"SABnzbd: {sab.get('jobs')} jobs, speed={sab.get('speed')}")
    if baz:
        ctx.append(f"Bazarr: {baz.get('episodes_missing',0)} episodes, "
                   f"{baz.get('movies_missing',0)} movies missing subs")
    if actions_taken:
        ctx.append(f"Auto-fixed: {'; '.join(actions_taken)}")
    ctx.append(f"Remaining issues: {'; '.join(issues) if issues else 'none'}")

    prompt = (
        "You are a concise NAS status assistant posting to a Discord #nas-digest channel. "
        "Write a SHORT plain-text message (3-5 lines max). "
        "Lead with overall status. Mention any auto-fixes applied. "
        "Call out remaining issues clearly. If all clear, one brief friendly line is fine. "
        "No markdown headers, no bullet symbols. Do not mention you are an AI.\n\n"
        + "\n".join(ctx)
    )

    url = "https://api.anthropic.com/v1/messages"
    payload = {
        "model": ANTHROPIC_MODEL,
        "max_tokens": 1024,
        "messages": [{"role": "user", "content": prompt}],
    }
    for attempt in range(3):
        try:
            resp = http_post(url, payload, {
                "x-api-key": ANTHROPIC_API_KEY,
                "anthropic-version": "2023-06-01",
            })
            return "".join(b["text"] for b in resp["content"]
                           if b.get("type") == "text").strip()
        except Exception as e:
            if attempt == 2:
                raise
            time.sleep(10)

# ── Discord post ──────────────────────────────────────────────────────────────

def post_discord(message):
    url = f"https://discord.com/api/v10/channels/{DIGEST_CHANNEL_ID}/messages"
    headers = {
        "Authorization": f"Bot {DISCORD_BOT_TOKEN}",
        "Content-Type": "application/json",
        "User-Agent": "DiscordBot (https://github.com/cneal/nas-guardian, 1.0)",
    }
    body = json.dumps({"content": message}).encode()
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    urllib.request.urlopen(req, timeout=15)

# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import sys
    digest_mode = "--digest" in sys.argv

    print(f"[{datetime.now()}] nas-guardian: {'digest' if digest_mode else 'remediation'} run")
    actions_taken = []

    # Phase 1: auto-remediation (every run)
    for action in fix_containers():
        print(f"  containers: {action}")
        actions_taken.append(action)

    if any("Restarted" in a for a in actions_taken):
        time.sleep(10)

    for fn in [fix_vpn_port, fix_dead_torrents, fix_indexer_circuit_breakers,
               fix_unpackarr, fix_sabnzbd_high_missing, fix_stuck_arr_queue,
               fix_readarr_completed_queue,
               fix_seerr_urls, fix_docker_images, fix_orphaned_incomplete]:
        try:
            result = fn()
            if result:
                print(f"  {fn.__name__}: {result}")
                actions_taken.append(result)
        except Exception as e:
            print(f"  {fn.__name__} exception: {e}")

    if not digest_mode:
        print(f"[{datetime.now()}] Done (remediation only)")
        sys.exit(0)

    # Phase 2: health check (digest runs only)
    print(f"[{datetime.now()}] Phase 2: health check")
    findings = check_all()
    print(f"  issues: {findings.get('issues', [])}")

    # Phase 3: summarise and post (digest runs only)
    print(f"[{datetime.now()}] Phase 3: Claude + Discord")
    try:
        summary = ai_summarise(findings, actions_taken)
        print(f"  summary: {summary}")
        post_discord(summary)
        print(f"[{datetime.now()}] Done — posted to #nas-digest")
    except Exception as e:
        import traceback
        traceback.print_exc()
        try:
            post_discord(f"⚠️ nas-guardian error: {e}")
        except Exception:
            pass
