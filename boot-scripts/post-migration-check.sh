#!/bin/bash
# post-migration-check.sh
# Run after first boot on new hardware (TerraMaster F6-424 Max)
# Usage: bash /boot/config/scripts/post-migration-check.sh

PASS=0
FAIL=0

ok()   { echo "  [OK]  $1"; ((PASS++)); }
fail() { echo "  [!!]  $1"; ((FAIL++)); }
info() { echo "  [--]  $1"; }
section() { echo; echo "=== $1 ==="; }

# ─── HARDWARE / BOOT ────────────────────────────────────────────────────────

section "Boot & Hardware"

# Confirm no GPU blacklists active
if grep -q 'modprobe.blacklist' /proc/cmdline; then
    fail "modprobe.blacklist still in kernel cmdline: $(grep -o 'modprobe.blacklist=[^ ]*' /proc/cmdline)"
else
    ok "No modprobe blacklists in kernel cmdline"
fi

# Check GPU driver loaded (good on new hardware)
if lsmod | grep -qE '^(i915|xe)\s'; then
    DRIVER=$(lsmod | grep -oE '^(i915|xe)' | head -1)
    ok "GPU driver loaded: $DRIVER (hardware transcoding may be available)"
else
    info "No Intel GPU driver loaded (i915/xe) — hardware transcoding unavailable"
fi

# Check /dev/dri
if ls /dev/dri/card0 /dev/dri/renderD128 &>/dev/null; then
    ok "/dev/dri devices present"
else
    info "/dev/dri not present — update Plex/Radarr container device mappings if HW transcode needed"
fi

# NIC / IP
CURRENT_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+' | head -1)
info "Current LAN IP: $CURRENT_IP"
if [ "$CURRENT_IP" = "192.168.86.46" ]; then
    ok "IP is 192.168.86.46 (DHCP reservation matched)"
else
    fail "IP is $CURRENT_IP — expected 192.168.86.46. Update Google Wifi DHCP reservation to new MAC:"
    ip link show | grep -A1 'state UP' | grep 'link/ether' | awk '{print "        MAC: "$2}'
fi

# ─── DOCKER CONTAINERS ──────────────────────────────────────────────────────

section "Docker Containers"

EXPECTED_CONTAINERS="Gluetun qbittorrent sonarr radarr prowlarr sabnzbd unpackarr cross-seed seer nas-bot flaresolverr"

for c in $EXPECTED_CONTAINERS; do
    STATE=$(docker inspect "$c" --format '{{.State.Status}}' 2>/dev/null)
    if [ "$STATE" = "running" ]; then
        ok "$c running"
    elif [ -z "$STATE" ]; then
        fail "$c not found"
    else
        fail "$c state: $STATE"
    fi
done

# ─── NETWORK NAMESPACES ─────────────────────────────────────────────────────

section "Network Namespace (netns containers)"

for c in qbittorrent sonarr prowlarr; do
    MODE=$(docker inspect "$c" --format '{{.HostConfig.NetworkMode}}' 2>/dev/null)
    if echo "$MODE" | grep -q '^container:'; then
        ok "$c shares netns with: ${MODE#container:}"
    else
        fail "$c not using container netns (mode: $MODE)"
    fi
done

# ─── MEDIANET IPs ───────────────────────────────────────────────────────────

section "medianet Static IPs"

check_ip() {
    local name=$1 expected=$2
    # Extract IP for the specific network containing the expected subnet
    local actual=$(docker inspect "$name" --format '{{json .NetworkSettings.Networks}}' 2>/dev/null | \
        python3 -c "import sys,json; nets=json.load(sys.stdin); print(next((v['IPAddress'] for v in nets.values() if v['IPAddress']), ''))" 2>/dev/null)
    # For multi-network containers, check if expected IP is present in any network
    local all_ips=$(docker inspect "$name" --format '{{json .NetworkSettings.Networks}}' 2>/dev/null | \
        python3 -c "import sys,json; nets=json.load(sys.stdin); print(' '.join(v['IPAddress'] for v in nets.values() if v['IPAddress']))" 2>/dev/null)
    if echo "$all_ips" | grep -qw "$expected"; then
        ok "$name IP: $expected"
    else
        fail "$name expected $expected, got: ${all_ips:-not found}"
    fi
}

check_ip Gluetun 172.20.0.2
check_ip radarr 172.20.0.3
check_ip flaresolverr 172.20.0.4
check_ip sabnzbd 172.20.0.10

# ─── SERVICE CONNECTIVITY ───────────────────────────────────────────────────

section "Service Connectivity"

check_http() {
    local name=$1 url=$2 expect_code=${3:-200}
    local code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
    # Accept 200, 301, 302, 307, 308 (redirects) and 401 (auth required) as "reachable"
    if [ "$code" = "$expect_code" ] || echo "200 301 302 307 308 401 403" | grep -qw "$code"; then
        ok "$name reachable (HTTP $code) ($url)"
    else
        fail "$name unreachable — got HTTP $code ($url)"
    fi
}

check_http "Sonarr"       "http://localhost:8989"
check_http "Radarr"       "http://172.20.0.3:7878"
check_http "sabnzbd"      "http://172.20.0.10:8080"
check_http "qBittorrent"  "http://localhost:8090"
check_http "Prowlarr"     "http://localhost:9696"
check_http "Seer"         "http://localhost:5055"
check_http "flaresolverr" "http://172.20.0.4:8191"

# ─── VPN / PORT FORWARDING ──────────────────────────────────────────────────

section "VPN & Port Forwarding"

VPN_PORT=$(docker exec Gluetun cat /tmp/gluetun/forwarded_port 2>/dev/null)
if [ -n "$VPN_PORT" ]; then
    ok "Gluetun forwarded port: $VPN_PORT"
    # Check qBit is using it
    QBIT_PORT=$(curl -s --max-time 5 -c /tmp/qbit-cookie \
        -d "username=${QB_USER:-cneal}&password=${QB_PASS:?QB_PASS not set}" \
        http://localhost:8090/api/v2/auth/login > /dev/null && \
        curl -s --max-time 5 -b /tmp/qbit-cookie \
        "http://localhost:8090/api/v2/app/preferences" | python3 -c "import sys,json; print(json.load(sys.stdin).get('listen_port','?'))" 2>/dev/null)
    if [ "$QBIT_PORT" = "$VPN_PORT" ]; then
        ok "qBittorrent listen port matches: $QBIT_PORT"
    else
        fail "qBittorrent port $QBIT_PORT does not match Gluetun port $VPN_PORT — gluetun-watch.sh may not be running"
    fi
else
    fail "Could not read Gluetun forwarded port"
fi

# Check firewalled status
FIREWALLED=$(curl -s --max-time 5 -b /tmp/qbit-cookie \
    "http://localhost:8090/api/v2/transfer/info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('connection_status','?'))" 2>/dev/null)
if [ "$FIREWALLED" = "connected" ]; then
    ok "qBittorrent connection status: connected"
elif [ "$FIREWALLED" = "firewalled" ]; then
    fail "qBittorrent is FIREWALLED — port forward not working yet"
else
    info "qBittorrent connection status: ${FIREWALLED:-unknown}"
fi

# ─── SABNZBD PROXY ──────────────────────────────────────────────────────────

section "sabnzbd Proxy (Sonarr download client)"

if curl -s --max-time 3 http://172.20.0.2:8085 &>/dev/null || \
   curl -s --max-time 3 -o /dev/null -w "%{http_code}" http://172.20.0.2:8085 | grep -qE '^(200|400|404|500)'; then
    ok "sabnzbd proxy reachable at 172.20.0.2:8085"
else
    fail "sabnzbd proxy NOT reachable at 172.20.0.2:8085 — restart with:"
    echo "        GLUETUN_PID=\$(docker inspect Gluetun --format '{{.State.Pid}}')"
    echo "        nsenter --net=/proc/\$GLUETUN_PID/ns/net -- python3 /usr/local/bin/sabnzbd-proxy.py &"
fi

# ─── PROWLARR INDEXER URLS ──────────────────────────────────────────────────

section "Prowlarr App URLs"

PROWLARR_APPS=$(curl -s --max-time 5 \
    -H "X-Api-Key: $(grep -r 'ApiKey' /mnt/cache/appdata/prowlarr/config.xml 2>/dev/null | grep -oP '(?<=<ApiKey>)[^<]+')" \
    "http://localhost:9696/api/v1/applications" 2>/dev/null)

if echo "$PROWLARR_APPS" | grep -q '192.168.86'; then
    fail "Prowlarr app URLs contain stale LAN IP (192.168.86.x) — update via Prowlarr Settings > Apps"
    echo "$PROWLARR_APPS" | python3 -c "
import sys, json
for a in json.load(sys.stdin):
    print(f'        {a[\"name\"]}: appUrl={a.get(\"fields\",[])[0].get(\"value\",\"?\") if a.get(\"fields\") else \"?\"}')
" 2>/dev/null
elif [ -n "$PROWLARR_APPS" ]; then
    ok "Prowlarr app URLs look clean"
else
    info "Could not check Prowlarr apps (API key not found or service down)"
fi

# ─── SYSLOG / PI ────────────────────────────────────────────────────────────

section "Remote Syslog (Pi)"

PI_IP="192.168.86.29"
if ping -c1 -W2 "$PI_IP" &>/dev/null; then
    ok "Pi reachable at $PI_IP"
    # Check rsyslog is forwarding
    if systemctl is-active rsyslog &>/dev/null; then
        ok "rsyslog running"
    fi
    info "Pi SSH:  ssh cnealen@192.168.86.29"
    info "Pi log:  /var/log/nas-remote.log"
    info "After boot: tail -f /var/log/nas-remote.log | grep $(hostname)"
    info "If NAS IP changed from 192.168.86.46, update Pi filter:"
    info "  sudo nano /etc/rsyslog.d/10-receive.conf  (update \$fromhost-ip)"
    info "  sudo systemctl restart rsyslog"
else
    fail "Pi NOT reachable at $PI_IP — remote syslog not logging"
    info "Pi SSH:  ssh cnealen@192.168.86.29"
    info "Pi log:  /var/log/nas-remote.log"
fi

# ─── SUMMARY ────────────────────────────────────────────────────────────────

section "Summary"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo
if [ $FAIL -eq 0 ]; then
    echo "  All checks passed. Migration looks good."
else
    echo "  $FAIL check(s) need attention. See [!!] items above."
fi
echo
