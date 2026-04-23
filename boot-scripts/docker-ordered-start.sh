#!/bin/bash
# Ordered Docker startup — ensures Gluetun is healthy before starting containers
# that share its network namespace (qbittorrent, sonarr, prowlarr).
# Runs in background from /boot/config/go after emhttp starts.

# Wait for Docker daemon
until docker info >/dev/null 2>&1; do sleep 2; done

# Wait for array (shfs) so all volume mounts are available
until mountpoint -q /mnt/user 2>/dev/null; do sleep 5; done

# --- Tier 1: Gluetun ---
if [ "$(docker inspect Gluetun --format '{{.State.Status}}' 2>/dev/null)" != "running" ]; then
    logger "docker-start: starting Gluetun"
    docker start Gluetun
fi

# Wait for Gluetun to be healthy (up to 120s)
TIMEOUT=120
ELAPSED=0
until [ "$(docker inspect Gluetun --format '{{.State.Health.Status}}' 2>/dev/null)" = "healthy" ]; do
    if [ $ELAPSED -ge $TIMEOUT ]; then
        logger "docker-start: Gluetun failed to become healthy after ${TIMEOUT}s — aborting"
        exit 1
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done
logger "docker-start: Gluetun healthy (${ELAPSED}s)"

# --- Tier 2: Gluetun network namespace containers ---
for container in qbittorrent sonarr prowlarr; do
    if [ "$(docker inspect $container --format '{{.State.Status}}' 2>/dev/null)" != "running" ]; then
        logger "docker-start: starting $container"
        docker start $container
    fi
done

sleep 3

# --- Tier 3: Everything else ---
for container in radarr flaresolverr plex cross-seed unpackarr seer bazarr nas-bot; do
    if [ "$(docker inspect $container --format '{{.State.Status}}' 2>/dev/null)" != "running" ]; then
        logger "docker-start: starting $container"
        docker start $container
    fi
done

logger "docker-start: all containers started"
