#!/bin/bash
# Reconnect qBittorrent, Sonarr, and Prowlarr whenever Gluetun starts/restarts.
# If a container just needs a restart (Gluetun was restarted), restart it.
# If restart fails because Gluetun was recreated (stale network namespace),
# recreate the container attached to the new Gluetun.
# Also watches the forwarded_port file for changes and syncs immediately.

QB_HOST="http://localhost:8090"
QB_USER="cneal"
QB_PASS="${QB_PASS:?QB_PASS not set}"

apply_port() {
    local PORT="$1"

    # Wait for qBittorrent WebUI to be ready (up to 60s)
    local i STATUS
    for i in $(seq 1 30); do
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$QB_HOST/api/v2/app/version")
        [ "$STATUS" = "200" ] && break
        sleep 2
    done

    local COOKIE
    COOKIE=$(curl -s -c - --data "username=$QB_USER&password=$QB_PASS" \
        "$QB_HOST/api/v2/auth/login" | awk '/SID/{print $7}')

    # Toggle to a temp port then back — forces qBittorrent to drop and rebind
    # its listen socket. Without this, the setting updates but the socket stays
    # bound to the old port (or stays unbound after a VPN server change).
    local TEMP_PORT=$(( PORT + 1 ))
    curl -s -b "SID=$COOKIE" \
        --data "json={\"listen_port\":$TEMP_PORT,\"random_port\":false,\"upnp\":false}" \
        "$QB_HOST/api/v2/app/setPreferences" > /dev/null
    sleep 1
    curl -s -b "SID=$COOKIE" \
        --data "json={\"listen_port\":$PORT,\"random_port\":false,\"upnp\":false}" \
        "$QB_HOST/api/v2/app/setPreferences" > /dev/null

    logger -t gluetun-watch "qBittorrent listen port set to $PORT"
}

sync_port() {
    local PORT i
    # Wait up to 60s for Gluetun to obtain a forwarded port
    for i in $(seq 1 30); do
        PORT=$(docker exec Gluetun cat /tmp/gluetun/forwarded_port 2>/dev/null)
        [ -n "$PORT" ] && break
        sleep 2
    done
    if [ -z "$PORT" ]; then
        logger -t gluetun-watch "No forwarded port after 60s, skipping port sync"
        return
    fi
    apply_port "$PORT"
}

# Background loop: watch for port file changes and sync immediately
port_watcher() {
    local LAST_PORT=""
    while true; do
        local PORT
        PORT=$(docker exec Gluetun cat /tmp/gluetun/forwarded_port 2>/dev/null)
        if [ -n "$PORT" ] && [ "$PORT" != "$LAST_PORT" ]; then
            logger -t gluetun-watch "Forwarded port changed to $PORT — syncing qBittorrent"
            apply_port "$PORT"
            LAST_PORT="$PORT"
        fi
        sleep 10
    done
}

# Recreate a container using its existing config but attached to the current Gluetun network.
# Used when Gluetun was recreated (not just restarted) and the old network namespace is gone.
recreate_container() {
    local NAME="$1"
    local IMAGE
    IMAGE=$(docker inspect "$NAME" --format '{{.Config.Image}}' 2>/dev/null)
    if [ -z "$IMAGE" ]; then
        logger -t gluetun-watch "$NAME: cannot recreate — container not found"
        return
    fi

    local ENV_ARGS=()
    while IFS= read -r env; do
        case "$env" in
            PATH=*|HOME=*|TERM=*|PS1=*|S6_*|LSIO_*|VIRTUAL_ENV=*|XDG_*) continue ;;
        esac
        ENV_ARGS+=(-e "$env")
    done < <(docker inspect "$NAME" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null)

    local VOL_ARGS=()
    while IFS= read -r bind; do
        [ -n "$bind" ] && VOL_ARGS+=(-v "$bind")
    done < <(docker inspect "$NAME" --format '{{range .HostConfig.Binds}}{{println .}}{{end}}' 2>/dev/null)

    docker rm -f "$NAME" 2>/dev/null
    docker run -d --name "$NAME" \
        --network container:Gluetun \
        "${ENV_ARGS[@]}" \
        "${VOL_ARGS[@]}" \
        --restart unless-stopped \
        "$IMAGE" > /dev/null
    logger -t gluetun-watch "$NAME: recreated on current Gluetun network"
}

# Try restart first. If it fails (container has stale Gluetun network), recreate it.
restart_or_recreate() {
    local NAME="$1"
    if docker restart "$NAME" 2>/dev/null; then
        logger -t gluetun-watch "$NAME: restarted"
    else
        logger -t gluetun-watch "$NAME: restart failed, recreating with current Gluetun network"
        recreate_container "$NAME"
    fi
}

PIDFILE="/var/run/gluetun-watch.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    logger -t gluetun-watch "Already running (pid $(cat "$PIDFILE")), exiting"
    exit 0
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

logger -t gluetun-watch "Watcher started"

# Start port watcher in background
port_watcher &

# Loop so we reconnect to docker events if Docker restarts
while true; do
    docker events \
        --filter "container=Gluetun" \
        --filter "event=start" \
        --format "{{.Time}}" | while read -r _; do
            logger -t gluetun-watch "Gluetun started — reconnecting dependents in 5s"
            sleep 5
            restart_or_recreate qbittorrent
            restart_or_recreate sonarr
            restart_or_recreate prowlarr
            logger -t gluetun-watch "Dependents reconnected — syncing port"
            sync_port
            docker restart plex
            logger -t gluetun-watch "Plex restarted"
    done
    logger -t gluetun-watch "docker events exited (Docker restarted?), reconnecting in 15s"
    sleep 15
done
