#!/bin/bash
# Updates Claude Code and persists the new binary to the USB flash drive.
set -e

echo "Downloading and installing Claude..."
curl -fsSL https://claude.ai/install.sh | bash

# Find the newly installed binary
LATEST=$(ls -t /root/.local/share/claude/versions/ | head -1)
if [ -z "$LATEST" ]; then
  echo "ERROR: No Claude version found in /root/.local/share/claude/versions/"
  exit 1
fi

echo "Persisting version $LATEST to /boot/config/claude..."
cp "/root/.local/share/claude/versions/$LATEST" /boot/config/claude

# Clean up the native install (won't survive reboot anyway, and avoids PATH conflict)
rm -f /root/.local/bin/claude
rm -rf /root/.local/share/claude

echo "Done. Claude $LATEST is now active and will persist across reboots."
