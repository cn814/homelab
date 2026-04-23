import os
import discord
from anthropic import Anthropic

DISCORD_TOKEN = os.environ["DISCORD_TOKEN"]
ANTHROPIC_API_KEY = os.environ["ANTHROPIC_API_KEY"]
CHANNEL_NAME = "claude-tasks"

intents = discord.Intents.default()
intents.message_content = True
client = discord.Client(intents=intents)
anthropic = Anthropic(api_key=ANTHROPIC_API_KEY)


@client.event
async def on_ready():
    print(f"Logged in as {client.user}")


@client.event
async def on_message(message):
    if message.author == client.user:
        return
    if message.channel.name != CHANNEL_NAME:
        return
    if not message.content.startswith("!claude"):
        return

    prompt = message.content[len("!claude"):].strip()
    if not prompt:
        await message.channel.send("Please provide a prompt after `!claude`.")
        return

    async with message.channel.typing():
        try:
            response = anthropic.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=1024,
                messages=[{"role": "user", "content": prompt}],
            )
            reply = response.content[0].text

            # Discord has a 2000 character limit
            while reply:
                await message.channel.send(reply[:2000])
                reply = reply[2000:]
        except Exception as e:
            await message.channel.send(f"Error: {e}")


client.run(DISCORD_TOKEN)
