FROM python:3.12-slim

WORKDIR /app

RUN pip install --no-cache-dir requests

COPY check_property.py .

RUN apt-get update && apt-get install -y --no-install-recommends cron && rm -rf /var/lib/apt/lists/*

ARG CRON_SCHEDULE="0 8 * * *"
RUN echo "${CRON_SCHEDULE} cd /app && python3 check_property.py >> /var/log/sdat-monitor.log 2>&1" > /etc/cron.d/sdat-monitor \
    && chmod 0644 /etc/cron.d/sdat-monitor \
    && crontab /etc/cron.d/sdat-monitor

CMD ["cron", "-f"]
