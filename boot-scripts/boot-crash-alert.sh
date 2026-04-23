#!/bin/bash
# Boot crash alert — detects unsafe shutdowns, grabs Pi logs, posts to Discord.
# Runs in background from /boot/config/go after emhttp starts.

BASELINE_FILE="/boot/config/last-unsafe-shutdowns"
DISCORD_TOKEN="${DISCORD_TOKEN:?DISCORD_TOKEN not set}"
DISCORD_CHANNEL="1348848014307098779"
PI_USER="cnealen"
PI_HOST="192.168.86.29"
PI_KEY="/root/.ssh/id_ed25519"

# Get current unsafe shutdown count
CURRENT=$(smartctl -a /dev/nvme0 2>/dev/null | awk '/Unsafe Shutdowns/{print $NF}')
if [ -z "$CURRENT" ]; then
    logger "boot-crash-alert: could not read SMART data"
    exit 1
fi

# Read baseline (if missing, write current and exit — first run)
if [ ! -f "$BASELINE_FILE" ]; then
    echo "$CURRENT" > "$BASELINE_FILE"
    logger "boot-crash-alert: baseline initialized at $CURRENT"
    exit 0
fi

BASELINE=$(cat "$BASELINE_FILE")

# Update baseline immediately so future boots compare from now
echo "$CURRENT" > "$BASELINE_FILE"

# No crash — clean shutdown
if [ "$CURRENT" -le "$BASELINE" ]; then
    logger "boot-crash-alert: clean boot (unsafe shutdowns unchanged at $CURRENT)"
    exit 0
fi

DIFF=$((CURRENT - BASELINE))
logger "boot-crash-alert: crash detected — unsafe shutdowns $BASELINE → $CURRENT (+$DIFF)"

# Wait for internet (up to 90s)
WAITED=0
until curl -s --max-time 5 https://discord.com >/dev/null 2>&1; do
    if [ $WAITED -ge 90 ]; then
        logger "boot-crash-alert: no internet after 90s, skipping Discord"
        exit 1
    fi
    sleep 5
    WAITED=$((WAITED + 5))
done

# Check pstore for kernel panic dumps
if ls /sys/fs/pstore/*.dmesg* 2>/dev/null | grep -q .; then
    PSTORE_STATUS="pstore dump present"
    PSTORE_SNIPPET=$(cat /sys/fs/pstore/*.dmesg* 2>/dev/null | tail -20)
else
    PSTORE_STATUS="pstore empty (hard lockup — kernel never panicked)"
    PSTORE_SNIPPET=""
fi

# Get last lines from Pi remote syslog (what the NAS was doing before crash)
PI_SYSLOG=$(ssh -i "$PI_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    "$PI_USER@$PI_HOST" "sudo tail -15 /var/log/nas-remote.log 2>/dev/null" 2>/dev/null)

# Build message
MSG="🚨 **NAS hard lockup detected**
Unsafe shutdowns: ${BASELINE} → ${CURRENT} (+${DIFF})
${PSTORE_STATUS}

**Last syslog before crash:**
\`\`\`
${PI_SYSLOG:-no data}
\`\`\`"

if [ -n "$PSTORE_SNIPPET" ]; then
    MSG="${MSG}
**pstore dump:**
\`\`\`
${PSTORE_SNIPPET}
\`\`\`"
fi

# Truncate to Discord's 2000 char limit
MSG="${MSG:0:1990}"

curl -s -X POST "https://discord.com/api/v10/channels/${DISCORD_CHANNEL}/messages" \
    -H "Authorization: Bot ${DISCORD_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"content\": $(python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' <<< "$MSG")}" \
    | logger -t boot-crash-alert
