FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    cron lm-sensors \
    && rm -rf /var/lib/apt/lists/*

COPY guardian.py .

RUN printf 'PATH=/usr/local/bin:/usr/bin:/bin\n*/15 * * * * cd /app && python3 guardian.py >> /var/log/nas-guardian.log 2>&1\n0 8,20 * * * cd /app && python3 guardian.py --digest >> /var/log/nas-guardian.log 2>&1\n' \
    > /etc/cron.d/nas-guardian \
    && chmod 0644 /etc/cron.d/nas-guardian \
    && crontab /etc/cron.d/nas-guardian

CMD ["cron", "-f"]
