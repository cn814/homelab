"""
NAS Guardian Discord Bot — Phase 4.1

Uses Gemini function calling for natural language understanding. Gemini decides
what tools to call and generates all responses. Claude is a last-resort fallback.

New in Phase 4.1:
  - "What should I watch?" — Gemini picks from your actual library by mood/genre
  - Recently added — last N days of imports; weekly Sunday digest
  - "Do I have X?" — instant library presence check
  - Bazarr subtitle status and search trigger
  - Plex active streams ("is anyone watching anything?")
"""

import asyncio
import os
import json
import urllib.request
import urllib.parse
import http.cookiejar
import time
import traceback
from datetime import datetime
from collections import defaultdict

# ── Config ────────────────────────────────────────────────────────────────────

DISCORD_BOT_TOKEN  = os.environ["DISCORD_BOT_TOKEN"]
DISCORD_CHANNEL_ID = int(os.environ["DISCORD_CHANNEL_ID"])

SONARR_URL = os.environ.get("SONARR_URL", "http://localhost:8989")
SONARR_KEY = os.environ["SONARR_KEY"]
RADARR_URL = os.environ.get("RADARR_URL", "http://localhost:7878")
RADARR_KEY = os.environ["RADARR_KEY"]
QBIT_URL   = os.environ.get("QBIT_URL", "http://localhost:8090")
QBIT_USER  = os.environ.get("QBIT_USER", "admin")
QBIT_PASS  = os.environ["QBIT_PASS"]

GEMINI_API_KEY    = os.environ["GEMINI_API_KEY"]
ANTHROPIC_API_KEY = os.environ["ANTHROPIC_API_KEY"]

BAZARR_URL = os.environ.get("BAZARR_URL", "http://localhost:6767")
BAZARR_KEY = os.environ["BAZARR_KEY"]
PLEX_URL   = os.environ.get("PLEX_URL", "http://localhost:32400")
PLEX_TOKEN = os.environ["PLEX_TOKEN"]

LOG_FILE = "/mnt/user/appdata/n8n/nas-bot.log"

GEMINI_MODEL     = "gemini-2.5-flash"
GEMINI_BASE_URL  = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}"

CONFIRM_TIMEOUT  = 60   # seconds to wait for yes/no
MAX_HISTORY      = 10   # messages per user (5 exchanges)
WEEKLY_DIGEST_DOW = 6   # Sunday (0=Mon … 6=Sun)
WEEKLY_DIGEST_HOUR = 10 # 10am local time

# ── Logging ───────────────────────────────────────────────────────────────────

def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass

# ── HTTP helpers ──────────────────────────────────────────────────────────────

def http_get(url, headers=None):
    req = urllib.request.Request(url, headers=headers or {})
    return json.loads(urllib.request.urlopen(req, timeout=15).read())

def http_post(url, data, headers=None):
    payload = json.dumps(data).encode() if not isinstance(data, bytes) else data
    h = {"Content-Type": "application/json", **(headers or {})}
    req = urllib.request.Request(url, data=payload, headers=h)
    return json.loads(urllib.request.urlopen(req, timeout=15).read())

def http_delete(url, headers=None):
    req = urllib.request.Request(url, headers=headers or {}, method="DELETE")
    urllib.request.urlopen(req, timeout=15)

def arr(service, path, method="GET", data=None):
    url, key = (SONARR_URL, SONARR_KEY) if service == "sonarr" else (RADARR_URL, RADARR_KEY)
    full = f"{url}/api/v3/{path}"
    h = {"X-Api-Key": key}
    if method == "GET":
        return http_get(full, h)
    if method == "POST":
        return http_post(full, data, h)
    if method == "DELETE":
        http_delete(full, h)
        return None

# ── qBittorrent session ───────────────────────────────────────────────────────

def qbit_session():
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    data = urllib.parse.urlencode({"username": QBIT_USER, "password": QBIT_PASS}).encode()
    resp = opener.open(f"{QBIT_URL}/api/v2/auth/login", data, timeout=10)
    if "Ok" not in resp.read().decode():
        raise RuntimeError("qBittorrent login failed")
    return opener

def qbit_get(opener, path):
    resp = opener.open(f"{QBIT_URL}/api/v2/{path}", timeout=15)
    raw = resp.read().decode()
    try:
        return json.loads(raw)
    except Exception:
        return raw

def qbit_post(opener, path, data):
    payload = urllib.parse.urlencode(data).encode()
    opener.open(f"{QBIT_URL}/api/v2/{path}", payload, timeout=15)

# ── Tool implementations ──────────────────────────────────────────────────────

def tool_get_stuck_downloads():
    results = []
    seen = set()
    for svc in ("sonarr", "radarr"):
        label = svc.capitalize()
        try:
            queue = arr(svc, "queue?page=1&pageSize=200")
            for item in queue.get("records", []):
                status  = item.get("status", "")
                tracked = item.get("trackedDownloadStatus", "")
                err     = item.get("errorMessage", "")
                if status in ("warning", "failed") or tracked == "warning" or err:
                    dl_id = item.get("downloadId") or item.get("title", "")[:40]
                    key = (label, dl_id)
                    if key in seen:
                        continue
                    seen.add(key)
                    results.append({
                        "source": label,
                        "title": item.get("title", "unknown")[:80],
                        "status": status,
                        "error": err or tracked,
                    })
        except Exception as e:
            results.append({"source": label, "error": str(e)})
    return {"count": len(results), "items": results}

def tool_get_active_downloads():
    try:
        opener = qbit_session()
        torrents = qbit_get(opener, "torrents/info?filter=downloading")
        if not isinstance(torrents, list):
            return {"error": "unexpected response from qBittorrent"}
        active = []
        for t in torrents:
            if t.get("state") not in ("downloading", "stalledDL", "forcedDL"):
                continue
            eta_s = t.get("eta", 8640000)
            eta = f"{eta_s//3600}h {(eta_s%3600)//60}m" if eta_s < 8640000 else "stalled"
            active.append({
                "name":       t.get("name", "")[:60],
                "progress":   f"{round(t.get('progress', 0) * 100, 1)}%",
                "size_gb":    round(t.get("size", 0) / 1e9, 2),
                "speed_mbps": round(t.get("dlspeed", 0) / 1e6, 2),
                "eta":        eta,
                "seeds":      t.get("num_seeds", 0) + t.get("num_complete", 0),
                "category":   t.get("category", ""),
            })
        return {"count": len(active), "downloads": active[:10]}
    except Exception as e:
        return {"error": str(e)}

def tool_get_disk_status():
    disks = {}
    for svc in ("sonarr", "radarr"):
        try:
            folders = arr(svc, "rootfolder")
            for f in folders:
                free_gb  = round(f.get("freeSpace",  0) / 1e9, 1)
                total_gb = round(f.get("totalSpace",  0) / 1e9, 1)
                used_pct = round(100 * (1 - f.get("freeSpace", 0) / max(f.get("totalSpace", 1), 1)), 1)
                disks[f.get("path", svc)] = {
                    "free_gb":  free_gb,
                    "total_gb": total_gb,
                    "used_pct": used_pct,
                    "warning":  used_pct >= DISK_WARN_PCT,
                }
        except Exception as e:
            disks[svc] = {"error": str(e)}
    return {"disks": disks}

def tool_get_library_stats():
    stats = {}
    try:
        series = arr("sonarr", "series")
        stats["tv"] = {
            "shows":                len(series),
            "total_episodes":       sum(s.get("statistics", {}).get("totalEpisodeCount", 0) for s in series),
            "downloaded_episodes":  sum(s.get("statistics", {}).get("episodeFileCount", 0) for s in series),
        }
        stats["tv"]["missing_episodes"] = stats["tv"]["total_episodes"] - stats["tv"]["downloaded_episodes"]
    except Exception as e:
        stats["tv"] = {"error": str(e)}
    try:
        movies = arr("radarr", "movie")
        downloaded = sum(1 for m in movies if m.get("hasFile"))
        stats["movies"] = {
            "total":      len(movies),
            "downloaded": downloaded,
            "missing":    len(movies) - downloaded,
        }
    except Exception as e:
        stats["movies"] = {"error": str(e)}
    return stats

def tool_search_show(query):
    try:
        results = arr("sonarr", f"series/lookup?term={urllib.parse.quote(query)}")
        return {"results": [
            {
                "title":    r.get("title"),
                "year":     r.get("year"),
                "tvdb_id":  r.get("tvdbId"),
                "status":   r.get("status"),
                "overview": (r.get("overview") or "")[:120],
            }
            for r in results[:5]
        ]}
    except Exception as e:
        return {"error": str(e)}

def tool_search_movie(query):
    try:
        results = arr("radarr", f"movie/lookup?term={urllib.parse.quote(query)}")
        return {"results": [
            {
                "title":    r.get("title"),
                "year":     r.get("year"),
                "tmdb_id":  r.get("tmdbId"),
                "overview": (r.get("overview") or "")[:120],
            }
            for r in results[:5]
        ]}
    except Exception as e:
        return {"error": str(e)}

def _sonarr_add(query, tvdb_id=None):
    term = f"tvdb:{tvdb_id}" if tvdb_id else query
    results = arr("sonarr", f"series/lookup?term={urllib.parse.quote(str(term))}")
    if not results:
        return {"error": f"No shows found for '{query}'"}
    show = results[0]
    title = show.get("title")
    tvdb  = show.get("tvdbId")
    existing = arr("sonarr", "series")
    if any(s.get("tvdbId") == tvdb for s in existing):
        return {"status": "already_exists", "title": title}
    folders  = arr("sonarr", "rootfolder")
    profiles = arr("sonarr", "qualityprofile")
    root = folders[0]["path"] if folders else "/mnt/user/Media/TV"
    pid  = profiles[0]["id"]  if profiles else 1
    arr("sonarr", "series", "POST", {
        **show,
        "rootFolderPath":  root,
        "qualityProfileId": pid,
        "monitored":        True,
        "addOptions":       {"searchForMissingEpisodes": True},
    })
    return {"status": "added", "title": title}

def _radarr_add(query, tmdb_id=None):
    term = f"tmdb:{tmdb_id}" if tmdb_id else query
    results = arr("radarr", f"movie/lookup?term={urllib.parse.quote(str(term))}")
    if not results:
        return {"error": f"No movies found for '{query}'"}
    movie = results[0]
    title = movie.get("title")
    tmdb  = movie.get("tmdbId")
    existing = arr("radarr", "movie")
    if any(m.get("tmdbId") == tmdb for m in existing):
        return {"status": "already_exists", "title": title}
    folders  = arr("radarr", "rootfolder")
    profiles = arr("radarr", "qualityprofile")
    root = folders[0]["path"] if folders else "/mnt/user/Media/Movies"
    pid  = profiles[0]["id"]  if profiles else 1
    arr("radarr", "movie", "POST", {
        **movie,
        "rootFolderPath":   root,
        "qualityProfileId": pid,
        "monitored":        True,
        "addOptions":       {"searchForMovie": True},
    })
    return {"status": "added", "title": title}

def tool_add_show(query, tvdb_id=None):
    try:
        return _sonarr_add(query, tvdb_id)
    except Exception as e:
        return {"error": str(e)}

def tool_add_movie(query, tmdb_id=None):
    try:
        return _radarr_add(query, tmdb_id)
    except Exception as e:
        return {"error": str(e)}

def tool_remove_show(query):
    try:
        series = arr("sonarr", "series")
        match = next((s for s in series if query.lower() in s.get("title", "").lower()), None)
        if not match:
            return {"error": f"No show matching '{query}' in Sonarr"}
        arr("sonarr", f"series/{match['id']}", "DELETE")
        return {"status": "removed", "title": match["title"]}
    except Exception as e:
        return {"error": str(e)}

def tool_remove_movie(query):
    try:
        movies = arr("radarr", "movie")
        match = next((m for m in movies if query.lower() in m.get("title", "").lower()), None)
        if not match:
            return {"error": f"No movie matching '{query}' in Radarr"}
        arr("radarr", f"movie/{match['id']}", "DELETE")
        return {"status": "removed", "title": match["title"]}
    except Exception as e:
        return {"error": str(e)}

def tool_pause_downloads():
    try:
        opener = qbit_session()
        opener.open(f"{QBIT_URL}/api/v2/torrents/pause?hashes=all", timeout=10)
        return {"status": "paused"}
    except Exception as e:
        return {"error": str(e)}

def tool_resume_downloads():
    try:
        opener = qbit_session()
        opener.open(f"{QBIT_URL}/api/v2/torrents/resume?hashes=all", timeout=10)
        return {"status": "resumed"}
    except Exception as e:
        return {"error": str(e)}

def tool_delete_dead_torrents():
    try:
        opener = qbit_session()
        torrents = qbit_get(opener, "torrents/info")
        dead = [
            t for t in torrents
            if t.get("state") in ("metaDL", "stalledDL")
            and (t.get("num_seeds", 0) + t.get("num_complete", 0)) == 0
        ]
        if not dead:
            return {"status": "none_found", "count": 0}
        hashes = "|".join(t["hash"] for t in dead)
        qbit_post(opener, "torrents/delete", {"hashes": hashes, "deleteFiles": "true"})
        return {
            "status":   "deleted",
            "count":    len(dead),
            "examples": [t["name"][:50] for t in dead[:3]],
        }
    except Exception as e:
        return {"error": str(e)}

def tool_trigger_missing_search():
    try:
        arr("sonarr", "command", "POST", {"name": "MissingEpisodeSearch"})
        return {"status": "triggered"}
    except Exception as e:
        return {"error": str(e)}

def tool_get_all_media():
    """Return a condensed list of available shows and movies for 'what should I watch'."""
    result = {}
    try:
        series = arr("sonarr", "series")
        result["shows"] = [
            {
                "title":   s.get("title"),
                "year":    s.get("year"),
                "genres":  s.get("genres", []),
                "status":  s.get("status"),
                "seasons": s.get("statistics", {}).get("seasonCount", 0),
                "overview": (s.get("overview") or "")[:100],
            }
            for s in series
            if s.get("statistics", {}).get("episodeFileCount", 0) > 0
        ]
    except Exception as e:
        result["shows_error"] = str(e)
    try:
        movies = arr("radarr", "movie")
        result["movies"] = [
            {
                "title":    m.get("title"),
                "year":     m.get("year"),
                "genres":   m.get("genres", []),
                "runtime":  m.get("runtime", 0),
                "overview": (m.get("overview") or "")[:100],
            }
            for m in movies
            if m.get("hasFile")
        ]
    except Exception as e:
        result["movies_error"] = str(e)
    return result

def tool_get_recently_added(days=7):
    """Return shows and movies imported in the last N days."""
    from datetime import timezone, timedelta
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    result = {"shows": [], "movies": [], "days": days}
    try:
        history = arr("sonarr", "history?page=1&pageSize=100&sortKey=date&sortDirection=descending&eventType=downloadFolderImported")
        seen = set()
        for r in history.get("records", []):
            dt = datetime.fromisoformat(r["date"].replace("Z", "+00:00"))
            if dt < cutoff:
                break
            series_title = r.get("series", {}).get("title", "?")
            ep = r.get("episode", {})
            key = (series_title, ep.get("seasonNumber"), ep.get("episodeNumber"))
            if key not in seen:
                seen.add(key)
                result["shows"].append({
                    "series":  series_title,
                    "episode": f"S{ep.get('seasonNumber',0):02}E{ep.get('episodeNumber',0):02}",
                    "title":   ep.get("title", ""),
                    "date":    r["date"][:10],
                })
    except Exception as e:
        result["shows_error"] = str(e)
    try:
        history = arr("radarr", "history?page=1&pageSize=50&sortKey=date&sortDirection=descending&eventType=downloadFolderImported")
        seen = set()
        for r in history.get("records", []):
            dt = datetime.fromisoformat(r["date"].replace("Z", "+00:00"))
            if dt < cutoff:
                break
            title = r.get("movie", {}).get("title", "?")
            if title not in seen:
                seen.add(title)
                result["movies"].append({"title": title, "date": r["date"][:10]})
    except Exception as e:
        result["movies_error"] = str(e)
    return result

def tool_check_library(query):
    """Check if a show or movie already exists in the local library."""
    q = query.lower()
    found = []
    try:
        for s in arr("sonarr", "series"):
            if q in s.get("title", "").lower():
                stats = s.get("statistics", {})
                found.append({
                    "type":      "show",
                    "title":     s["title"],
                    "year":      s.get("year"),
                    "status":    s.get("status"),
                    "seasons":   stats.get("seasonCount", 0),
                    "episodes":  f"{stats.get('episodeFileCount',0)}/{stats.get('totalEpisodeCount',0)}",
                    "monitored": s.get("monitored"),
                })
    except Exception as e:
        found.append({"error": f"Sonarr: {e}"})
    try:
        for m in arr("radarr", "movie"):
            if q in m.get("title", "").lower():
                found.append({
                    "type":       "movie",
                    "title":      m["title"],
                    "year":       m.get("year"),
                    "downloaded": m.get("hasFile", False),
                    "monitored":  m.get("monitored"),
                })
    except Exception as e:
        found.append({"error": f"Radarr: {e}"})
    return {"query": query, "found": found, "count": len(found)}

def tool_get_subtitle_status(query):
    """Check subtitle status for a show or movie in Bazarr."""
    q = query.lower()
    results = []
    try:
        series = http_get(f"{BAZARR_URL}/api/series?apikey={BAZARR_KEY}")
        for s in series.get("data", []):
            if q in s.get("title", "").lower():
                results.append({
                    "type":          "show",
                    "title":         s.get("title"),
                    "missing_count": s.get("episodeMissingCount", 0),
                    "sonarr_id":     s.get("sonarrSeriesId"),
                })
    except Exception as e:
        results.append({"error": f"Bazarr series: {e}"})
    try:
        movies = http_get(f"{BAZARR_URL}/api/movies?apikey={BAZARR_KEY}")
        for m in movies.get("data", []):
            if q in m.get("title", "").lower():
                missing = [s.get("name") for s in m.get("missing_subtitles", [])]
                results.append({
                    "type":             "movie",
                    "title":            m.get("title"),
                    "missing_subtitles": missing,
                    "has_subtitles":    len(m.get("subtitles", [])) > 0,
                    "radarr_id":        m.get("radarrId"),
                })
    except Exception as e:
        results.append({"error": f"Bazarr movies: {e}"})
    return {"query": query, "results": results}

def tool_search_subtitles(query):
    """Trigger Bazarr to search for subtitles for a show or movie."""
    q = query.lower()
    triggered = []
    try:
        series = http_get(f"{BAZARR_URL}/api/series?apikey={BAZARR_KEY}")
        for s in series.get("data", []):
            if q in s.get("title", "").lower() and s.get("episodeMissingCount", 0) > 0:
                sid = s.get("sonarrSeriesId")
                http_post(
                    f"{BAZARR_URL}/api/series/subtitles?apikey={BAZARR_KEY}",
                    {"seriesid[]": sid, "action": "search"},
                    {},
                )
                triggered.append({"type": "show", "title": s.get("title"), "sonarr_id": sid})
    except Exception as e:
        triggered.append({"error": f"Bazarr series: {e}"})
    try:
        movies = http_get(f"{BAZARR_URL}/api/movies?apikey={BAZARR_KEY}")
        for m in movies.get("data", []):
            if q in m.get("title", "").lower() and m.get("missing_subtitles"):
                rid = m.get("radarrId")
                http_post(
                    f"{BAZARR_URL}/api/movies/subtitles?apikey={BAZARR_KEY}",
                    {"radarrid[]": rid, "action": "search"},
                    {},
                )
                triggered.append({"type": "movie", "title": m.get("title"), "radarr_id": rid})
    except Exception as e:
        triggered.append({"error": f"Bazarr movies: {e}"})
    if not triggered:
        return {"status": "nothing_to_search", "note": "No missing subtitles found for that title"}
    return {"status": "triggered", "items": triggered}

def tool_get_active_streams():
    """Get currently active Plex streams."""
    try:
        from xml.etree import ElementTree as ET
        req = urllib.request.Request(
            f"{PLEX_URL}/status/sessions",
            headers={"X-Plex-Token": PLEX_TOKEN, "Accept": "application/xml"},
        )
        tree = ET.parse(urllib.request.urlopen(req, timeout=10))
        root = tree.getroot()
        sessions = []
        for v in root.findall(".//*[@ratingKey]"):
            media_type = v.get("type", "")
            if media_type not in ("episode", "movie", "clip"):
                continue
            user_el = v.find(".//User")
            player_el = v.find(".//Player")
            ts_el = v.find(".//TranscodeSession")
            if media_type == "episode":
                title = f"{v.get('grandparentTitle','')} {v.get('parentTitle','')} - {v.get('title','')}"
            else:
                title = v.get("title", "?")
            sessions.append({
                "title":        title,
                "type":         media_type,
                "user":         user_el.get("title", "?") if user_el is not None else "?",
                "player":       player_el.get("title", "?") if player_el is not None else "?",
                "state":        player_el.get("state", "?") if player_el is not None else "?",
                "transcoding":  ts_el is not None,
                "progress_pct": round(int(v.get("viewOffset", 0)) / max(int(v.get("duration", 1)), 1) * 100, 1),
            })
        return {"active_streams": sessions, "count": len(sessions)}
    except Exception as e:
        return {"error": str(e)}

# ── Tool registry ─────────────────────────────────────────────────────────────

# Tools that require user confirmation before executing
CONFIRM_REQUIRED = {
    "add_show", "add_movie",
    "remove_show", "remove_movie",
    "pause_downloads", "delete_dead_torrents",
}

TOOL_FN = {
    "get_stuck_downloads":    lambda a: tool_get_stuck_downloads(),
    "get_active_downloads":   lambda a: tool_get_active_downloads(),
    "get_disk_status":        lambda a: tool_get_disk_status(),
    "get_library_stats":      lambda a: tool_get_library_stats(),
    "search_show":            lambda a: tool_search_show(a["query"]),
    "search_movie":           lambda a: tool_search_movie(a["query"]),
    "add_show":               lambda a: tool_add_show(a["query"], a.get("tvdb_id")),
    "add_movie":              lambda a: tool_add_movie(a["query"], a.get("tmdb_id")),
    "remove_show":            lambda a: tool_remove_show(a["query"]),
    "remove_movie":           lambda a: tool_remove_movie(a["query"]),
    "pause_downloads":        lambda a: tool_pause_downloads(),
    "resume_downloads":       lambda a: tool_resume_downloads(),
    "delete_dead_torrents":   lambda a: tool_delete_dead_torrents(),
    "trigger_missing_search": lambda a: tool_trigger_missing_search(),
    "get_all_media":          lambda a: tool_get_all_media(),
    "get_recently_added":     lambda a: tool_get_recently_added(int(a.get("days", 7))),
    "check_library":          lambda a: tool_check_library(a["query"]),
    "get_subtitle_status":    lambda a: tool_get_subtitle_status(a["query"]),
    "search_subtitles":       lambda a: tool_search_subtitles(a["query"]),
    "get_active_streams":     lambda a: tool_get_active_streams(),
}

# ── Gemini function calling ────────────────────────────────────────────────────

SYSTEM_PROMPT = """You are NAS Guardian, a helpful Discord bot that manages a home Unraid NAS server.
You control Sonarr (TV shows), Radarr (movies), and qBittorrent downloads.

Keep responses concise and use Discord markdown. Stay under 1800 characters.
Use emojis sparingly but effectively.
For destructive actions (add, remove, pause, delete), call the tool — confirmation will be requested automatically.
When adding media, search first to confirm the right title before adding.
If you can't do something, briefly explain what you CAN do."""

TOOLS_SCHEMA = [{
    "function_declarations": [
        {
            "name": "get_stuck_downloads",
            "description": "Get all stuck, errored, or stalled downloads from Sonarr and Radarr queues",
            "parameters": {"type": "OBJECT", "properties": {}},
        },
        {
            "name": "get_active_downloads",
            "description": "Get currently active downloads with progress percentage, speed, and ETA",
            "parameters": {"type": "OBJECT", "properties": {}},
        },
        {
            "name": "get_disk_status",
            "description": "Get disk space usage and free space for TV and movie storage",
            "parameters": {"type": "OBJECT", "properties": {}},
        },
        {
            "name": "get_library_stats",
            "description": "Get library statistics: number of shows, movies, and episodes",
            "parameters": {"type": "OBJECT", "properties": {}},
        },
        {
            "name": "search_show",
            "description": "Search for a TV show by name. Returns results with TVDB IDs.",
            "parameters": {
                "type": "OBJECT",
                "properties": {"query": {"type": "STRING", "description": "Show title to search for"}},
                "required": ["query"],
            },
        },
        {
            "name": "search_movie",
            "description": "Search for a movie by name. Returns results with TMDB IDs.",
            "parameters": {
                "type": "OBJECT",
                "properties": {"query": {"type": "STRING", "description": "Movie title to search for"}},
                "required": ["query"],
            },
        },
        {
            "name": "add_show",
            "description": "Add a TV show to Sonarr for monitoring and downloading. Will ask for user confirmation.",
            "parameters": {
                "type": "OBJECT",
                "properties": {
                    "query":   {"type": "STRING",  "description": "Show title"},
                    "tvdb_id": {"type": "INTEGER", "description": "TVDB ID if known from a prior search"},
                },
                "required": ["query"],
            },
        },
        {
            "name": "add_movie",
            "description": "Add a movie to Radarr for monitoring and downloading. Will ask for user confirmation.",
            "parameters": {
                "type": "OBJECT",
                "properties": {
                    "query":   {"type": "STRING",  "description": "Movie title"},
                    "tmdb_id": {"type": "INTEGER", "description": "TMDB ID if known from a prior search"},
                },
                "required": ["query"],
            },
        },
        {
            "name": "remove_show",
            "description": "Remove a TV show from Sonarr (keeps downloaded files). Will ask for confirmation.",
            "parameters": {
                "type": "OBJECT",
                "properties": {"query": {"type": "STRING", "description": "Show title to remove"}},
                "required": ["query"],
            },
        },
        {
            "name": "remove_movie",
            "description": "Remove a movie from Radarr (keeps downloaded files). Will ask for confirmation.",
            "parameters": {
                "type": "OBJECT",
                "properties": {"query": {"type": "STRING", "description": "Movie title to remove"}},
                "required": ["query"],
            },
        },
        {
            "name": "pause_downloads",
            "description": "Pause all active downloads in qBittorrent. Will ask for confirmation.",
            "parameters": {"type": "OBJECT", "properties": {}},
        },
        {
            "name": "resume_downloads",
            "description": "Resume all paused downloads in qBittorrent",
            "parameters": {"type": "OBJECT", "properties": {}},
        },
        {
            "name": "delete_dead_torrents",
            "description": "Delete torrents with 0 seeds that will never complete. Will ask for confirmation.",
            "parameters": {"type": "OBJECT", "properties": {}},
        },
        {
            "name": "trigger_missing_search",
            "description": "Tell Sonarr to search for all monitored missing episodes",
            "parameters": {"type": "OBJECT", "properties": {}},
        },
        {
            "name": "get_all_media",
            "description": "Get the full list of available shows and movies in the library. Use this to answer 'what should I watch' or mood/genre-based recommendations.",
            "parameters": {"type": "OBJECT", "properties": {}},
        },
        {
            "name": "get_recently_added",
            "description": "Get shows and movies added/imported in the last N days",
            "parameters": {
                "type": "OBJECT",
                "properties": {"days": {"type": "INTEGER", "description": "Number of days to look back (default 7)"}},
            },
        },
        {
            "name": "check_library",
            "description": "Check if a specific show or movie already exists in the library (Sonarr/Radarr)",
            "parameters": {
                "type": "OBJECT",
                "properties": {"query": {"type": "STRING", "description": "Title to look up"}},
                "required": ["query"],
            },
        },
        {
            "name": "get_subtitle_status",
            "description": "Check subtitle status for a show or movie in Bazarr — whether subtitles are present or missing",
            "parameters": {
                "type": "OBJECT",
                "properties": {"query": {"type": "STRING", "description": "Show or movie title"}},
                "required": ["query"],
            },
        },
        {
            "name": "search_subtitles",
            "description": "Trigger Bazarr to search for missing subtitles for a show or movie",
            "parameters": {
                "type": "OBJECT",
                "properties": {"query": {"type": "STRING", "description": "Show or movie title"}},
                "required": ["query"],
            },
        },
        {
            "name": "get_active_streams",
            "description": "Get currently active Plex streams — who is watching what right now",
            "parameters": {"type": "OBJECT", "properties": {}},
        },
    ]
}]


def _gemini_request(contents):
    """Send a request to Gemini and return the raw response dict."""
    payload = json.dumps({
        "contents": contents,
        "tools": TOOLS_SCHEMA,
        "system_instruction": {"parts": [{"text": SYSTEM_PROMPT}]},
        "generationConfig": {"temperature": 0.3, "maxOutputTokens": 1000},
    }).encode()
    req = urllib.request.Request(
        f"{GEMINI_BASE_URL}:generateContent?key={GEMINI_API_KEY}",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    for attempt in range(3):
        try:
            return json.loads(urllib.request.urlopen(req, timeout=30).read())
        except urllib.error.HTTPError as e:
            body = e.read().decode()
            log(f"Gemini HTTP {e.code}: {body[:200]}")
            if e.code == 429 and attempt < 2:
                time.sleep(30)
            else:
                raise
    return None


def _parse_candidate(resp):
    """
    Extract what Gemini wants to do.
    Returns ("text", str) or ("function_call", {name, args, model_content}).
    """
    if not resp or "candidates" not in resp:
        return "text", None
    candidate = resp["candidates"][0]
    model_content = candidate.get("content", {})
    parts = model_content.get("parts", [])
    for part in parts:
        if "functionCall" in part:
            return "function_call", {
                "name":          part["functionCall"]["name"],
                "args":          part["functionCall"].get("args", {}),
                "model_content": model_content,
            }
    text = "".join(p.get("text", "") for p in parts)
    return "text", text or None


def run_gemini_turn(contents):
    """
    Run a Gemini turn, handling chained tool calls (max 5).

    Returns one of:
      ("text",    reply_str,  updated_contents)
      ("confirm", fn_name,    fn_args, partial_contents, model_content)
    """
    for _ in range(5):
        resp = _gemini_request(contents)
        if not resp:
            return "text", "❌ Gemini didn't respond.", contents

        kind, value = _parse_candidate(resp)

        if kind == "text":
            updated = contents + [{"role": "model", "parts": [{"text": value or ""}]}]
            return "text", value or "🤷 I'm not sure how to respond to that.", updated

        # It's a function call
        fn_name      = value["name"]
        fn_args      = value["args"]
        model_content = value["model_content"]
        log(f"Gemini → tool: {fn_name}({json.dumps(fn_args)[:100]})")

        if fn_name in CONFIRM_REQUIRED:
            return "confirm", fn_name, fn_args, contents, model_content

        # Execute non-destructive tool
        fn = TOOL_FN.get(fn_name)
        if fn:
            try:
                result = fn(fn_args)
            except Exception as e:
                result = {"error": str(e)}
        else:
            result = {"error": f"Unknown tool: {fn_name}"}
        log(f"Tool result: {json.dumps(result)[:200]}")

        # Feed result back to Gemini
        contents = contents + [
            model_content,
            {
                "role": "user",
                "parts": [{"functionResponse": {"name": fn_name, "response": {"result": result}}}],
            },
        ]

    return "text", "❌ Got stuck in too many tool calls.", contents


def gemini_complete_confirmed(fn_name, fn_args, partial_contents, model_content):
    """Execute a confirmed action and get Gemini's response."""
    fn = TOOL_FN.get(fn_name)
    try:
        result = fn(fn_args) if fn else {"error": f"Unknown tool: {fn_name}"}
    except Exception as e:
        result = {"error": str(e)}
    log(f"Confirmed tool result: {json.dumps(result)[:200]}")

    contents = partial_contents + [
        model_content,
        {
            "role": "user",
            "parts": [{"functionResponse": {"name": fn_name, "response": {"result": result}}}],
        },
    ]
    # Get Gemini's natural language response
    kind, text, updated = run_gemini_turn(contents)
    return text or "✅ Done.", updated


# ── Claude fallback ───────────────────────────────────────────────────────────

def ask_claude_fallback(user_text):
    """Last-resort fallback when Gemini is completely unavailable."""
    payload = json.dumps({
        "model": "claude-haiku-4-5-20251001",
        "max_tokens": 512,
        "messages": [{
            "role": "user",
            "content": f"You are NAS Guardian, a home media server Discord bot. "
                       f"Gemini AI is currently unavailable. "
                       f"Tell the user you're having trouble connecting to your AI brain and "
                       f"suggest they try: stuck items, search show/movie, add show/movie, "
                       f"download status, disk status, or library stats. "
                       f"User said: {user_text}",
        }],
    }).encode()
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=payload,
        headers={
            "Content-Type": "application/json",
            "x-api-key": ANTHROPIC_API_KEY,
            "anthropic-version": "2023-06-01",
        },
    )
    resp = json.loads(urllib.request.urlopen(req, timeout=20).read())
    return resp["content"][0]["text"]

# ── State ─────────────────────────────────────────────────────────────────────

# user_id -> list of Gemini content dicts (trimmed to MAX_HISTORY)
conversation_history: dict[int, list] = defaultdict(list)

# user_id -> {fn_name, fn_args, partial_contents, model_content, expires, description}
pending_confirmations: dict[int, dict] = {}


YES_WORDS = {"yes", "y", "confirm", "ok", "sure", "yep", "yeah", "do it", "go ahead"}
NO_WORDS  = {"no", "n", "cancel", "nope", "nah", "stop", "abort"}

def _trim_history(user_id: int):
    h = conversation_history[user_id]
    if len(h) > MAX_HISTORY:
        conversation_history[user_id] = h[-MAX_HISTORY:]

def _confirm_description(fn_name: str, fn_args: dict) -> str:
    q = fn_args.get("query", "")
    return {
        "add_show":           f"➕ Add **{q}** to Sonarr?",
        "add_movie":          f"➕ Add **{q}** to Radarr?",
        "remove_show":        f"🗑️ Remove **{q}** from Sonarr (keeps files)?",
        "remove_movie":       f"🗑️ Remove **{q}** from Radarr (keeps files)?",
        "pause_downloads":    "⏸️ Pause **all** downloads?",
        "delete_dead_torrents": "🧹 Delete all 0-seed torrents that can never complete?",
    }.get(fn_name, f"Confirm **{fn_name}**?") + " Reply `yes` or `no`."

# ── Discord bot ───────────────────────────────────────────────────────────────

try:
    import discord
except ImportError:
    import subprocess as _sp
    _sp.run(["pip", "install", "discord.py", "--break-system-packages", "-q"], check=True)
    import discord

intents = discord.Intents.default()
intents.message_content = True
intents.dm_messages = True
client = discord.Client(intents=intents)


@client.event
async def on_ready():
    log(f"NAS Guardian online as {client.user} (ID: {client.user.id})")
    client.loop.create_task(weekly_digest())


@client.event
async def on_message(message):
    if message.author == client.user:
        return

    is_dm = isinstance(message.channel, discord.DMChannel)

    if is_dm:
        user_text = message.content.strip()
        if not user_text:
            return
    else:
        if client.user not in message.mentions:
            return
        if message.channel.id != DISCORD_CHANNEL_ID:
            return
        user_text = (
            message.content
            .replace(f"<@{client.user.id}>", "")
            .replace(f"<@!{client.user.id}>", "")
            .strip()
        )

    user_id = message.author.id
    log(f"[{'DM' if is_dm else 'CH'}] {message.author}: {user_text[:100]}")

    # ── Confirmation flow ─────────────────────────────────────────────────────
    pending = pending_confirmations.get(user_id)
    if pending:
        if time.time() > pending["expires"]:
            del pending_confirmations[user_id]
        elif user_text.lower() in YES_WORDS:
            del pending_confirmations[user_id]
            async with message.channel.typing():
                try:
                    reply, updated = await asyncio.get_event_loop().run_in_executor(
                        None,
                        gemini_complete_confirmed,
                        pending["fn_name"],
                        pending["fn_args"],
                        pending["partial_contents"],
                        pending["model_content"],
                    )
                    conversation_history[user_id] = updated[-MAX_HISTORY:]
                except Exception as e:
                    log(f"Confirmed action error: {e}\n{traceback.format_exc()}")
                    reply = f"❌ Something went wrong: {e}"
            await message.channel.send(reply[:1990])
            return
        elif user_text.lower() in NO_WORDS:
            del pending_confirmations[user_id]
            await message.channel.send("❌ Cancelled.")
            return

    # ── Build Gemini contents ─────────────────────────────────────────────────
    history = list(conversation_history[user_id])
    history.append({"role": "user", "parts": [{"text": user_text}]})

    # ── Run Gemini turn ───────────────────────────────────────────────────────
    async with message.channel.typing():
        try:
            result = await asyncio.get_event_loop().run_in_executor(
                None, run_gemini_turn, history
            )
        except Exception as e:
            log(f"Gemini error: {e}\n{traceback.format_exc()}")
            try:
                fallback = await asyncio.get_event_loop().run_in_executor(
                    None, ask_claude_fallback, user_text
                )
                await message.channel.send(fallback[:1990])
            except Exception:
                await message.channel.send("❌ Both AI backends are unavailable right now.")
            return

    if result[0] == "confirm":
        _, fn_name, fn_args, partial_contents, model_content = result
        desc = _confirm_description(fn_name, fn_args)
        pending_confirmations[user_id] = {
            "fn_name":         fn_name,
            "fn_args":         fn_args,
            "partial_contents": partial_contents,
            "model_content":   model_content,
            "expires":         time.time() + CONFIRM_TIMEOUT,
        }
        await message.channel.send(desc)

    elif result[0] == "text":
        _, reply, updated_history = result
        conversation_history[user_id] = updated_history[-MAX_HISTORY:]
        await message.channel.send((reply or "🤷 No response.")[:1990])


async def weekly_digest():
    """Post a 'what was added this week' summary every Sunday morning."""
    await asyncio.sleep(30)
    channel = None
    while channel is None:
        channel = client.get_channel(DISCORD_CHANNEL_ID)
        if channel is None:
            await asyncio.sleep(5)

    log("Weekly digest task started.")

    while True:
        now = datetime.now()
        # Calculate seconds until next Sunday at WEEKLY_DIGEST_HOUR
        days_until = (WEEKLY_DIGEST_DOW - now.weekday()) % 7
        if days_until == 0 and now.hour >= WEEKLY_DIGEST_HOUR:
            days_until = 7
        target = now.replace(hour=WEEKLY_DIGEST_HOUR, minute=0, second=0, microsecond=0)
        from datetime import timedelta
        target += timedelta(days=days_until)
        wait_secs = (target - now).total_seconds()
        log(f"Weekly digest: next run in {wait_secs/3600:.1f}h")
        await asyncio.sleep(wait_secs)

        try:
            loop = asyncio.get_event_loop()
            data = await loop.run_in_executor(None, lambda: tool_get_recently_added(7))
            shows  = data.get("shows", [])
            movies = data.get("movies", [])

            if not shows and not movies:
                log("Weekly digest: nothing added this week, skipping post")
                continue

            lines = ["📺 **Weekly NAS Digest** — here's what was added this week:\n"]
            if movies:
                lines.append(f"**🎬 Movies ({len(movies)}):**")
                for m in movies:
                    lines.append(f"• {m['title']} ({m['date']})")
            if shows:
                # Group by series
                from collections import defaultdict as dd
                by_series = dd(list)
                for ep in shows:
                    by_series[ep["series"]].append(ep["episode"])
                lines.append(f"\n**📺 TV Episodes ({len(shows)}):**")
                for series, eps in sorted(by_series.items()):
                    eps_str = ", ".join(sorted(eps)[:6])
                    if len(eps) > 6:
                        eps_str += f" +{len(eps)-6} more"
                    lines.append(f"• **{series}** — {eps_str}")

            await channel.send("\n".join(lines)[:1990])
            log(f"Weekly digest posted: {len(movies)} movies, {len(shows)} episodes")
        except Exception as e:
            log(f"Weekly digest error: {e}")

# ── Entry point ───────────────────────────────────────────────────────────────

log("=== NAS Guardian Phase 4 starting ===")
client.run(DISCORD_BOT_TOKEN)
