#!/bin/bash
# Recreate sdat-monitor container after migration
# Image saved at: /mnt/user/appdata/sdat-monitor/sdat-monitor-image.tar.gz

# Step 1 — load the image (only needed if Docker doesn't already have it)
if ! docker image inspect sdat-monitor &>/dev/null; then
    echo "Loading sdat-monitor image..."
    docker load < /mnt/user/appdata/sdat-monitor/sdat-monitor-image.tar.gz
fi

# Step 2 — recreate the container
docker run -d \
  --name sdat-monitor \
  --restart unless-stopped \
  -v /mnt/user/appdata/sdat-monitor/data:/data \
  -e "EMAIL_FROM=cnealen@gmail.com" \
  -e "EMAIL_TO=cnealen@gmail.com" \
  -e "EMAIL_PASS=fyrafxyuwvapqfln" \
  sdat-monitor cron -f

echo "Done."
