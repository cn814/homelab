FROM python:3.12-slim

# Install discord.py
RUN pip install --no-cache-dir discord.py

# Working dir
WORKDIR /app

# Bot script is mounted at runtime from host, not baked in —
# so you can edit it without rebuilding the image
CMD ["python3", "-u", "/app/nas-bot.py"]
