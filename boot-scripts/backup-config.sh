#!/bin/bash
# Backs up /boot/config to the array, keeping last 30 snapshots.
DEST=/mnt/user/appdata/config-snapshots
SNAPSHOT="$DEST/boot-config-$(date +%Y%m%d-%H%M%S).tar.gz"

mkdir -p "$DEST"

tar czf "$SNAPSHOT" \
  --exclude='*.txz' \
  --exclude='*.tgz' \
  --exclude='/boot/config/claude' \
  --exclude='/boot/config/plugins/dwpython' \
  --exclude='/boot/config/plugins/tailscale/state' \
  --exclude='/boot/config/plugins/unraid-management-agent' \
  --exclude='/boot/config/plugins/intel-gpu-top' \
  /boot/config/ 2>/dev/null

# Keep only the 30 most recent snapshots
ls -t "$DEST"/boot-config-*.tar.gz 2>/dev/null | tail -n +31 | xargs rm -f
