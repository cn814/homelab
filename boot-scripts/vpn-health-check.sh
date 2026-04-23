#!/bin/bash
# VPN health check — restarts Gluetun if packet loss or latency is too high.
# Intended to run hourly via cron.

LOSS_THRESHOLD=10      # % packet loss to trigger restart
LATENCY_THRESHOLD=200  # ms avg latency to trigger restart
LOG_TAG="vpn-health"

PING_OUTPUT=$(docker exec qbittorrent ping -c 10 8.8.8.8 2>/dev/null)
if [ -z "$PING_OUTPUT" ]; then
    logger -t "$LOG_TAG" "Could not ping from qBittorrent container — skipping"
    exit 0
fi

LOSS=$(echo "$PING_OUTPUT" | grep -oP '\d+(?=% packet loss)')
AVG_LATENCY=$(echo "$PING_OUTPUT" | grep -oP 'avg = \K[\d.]+' | head -1)
# Handle different ping output formats
[ -z "$AVG_LATENCY" ] && AVG_LATENCY=$(echo "$PING_OUTPUT" | grep -oP 'min/avg/max = [\d.]+/\K[\d.]+')

logger -t "$LOG_TAG" "VPN check: loss=${LOSS}% latency=${AVG_LATENCY}ms (thresholds: loss>${LOSS_THRESHOLD}% or latency>${LATENCY_THRESHOLD}ms)"

RESTART=0
[ -n "$LOSS" ] && [ "$LOSS" -gt "$LOSS_THRESHOLD" ] && RESTART=1
if [ -n "$AVG_LATENCY" ]; then
    AVG_INT=${AVG_LATENCY%.*}
    [ "$AVG_INT" -gt "$LATENCY_THRESHOLD" ] && RESTART=1
fi

if [ "$RESTART" -eq 1 ]; then
    logger -t "$LOG_TAG" "Poor VPN quality (loss=${LOSS}% latency=${AVG_LATENCY}ms) — restarting Gluetun"
    docker restart Gluetun
    sleep 25
    NEW_PING=$(docker exec qbittorrent ping -c 4 8.8.8.8 2>/dev/null | tail -2)
    NEW_PORT=$(docker exec Gluetun cat /tmp/gluetun/forwarded_port 2>/dev/null)
    logger -t "$LOG_TAG" "Gluetun restarted — new port: ${NEW_PORT} | $NEW_PING"
else
    logger -t "$LOG_TAG" "VPN quality OK — no action needed"
fi
