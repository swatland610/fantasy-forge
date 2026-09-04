import os

import httpx
from mcp.server.fastmcp import FastMCP

DISCORD_BASE = "https://discord.com/api/v10"
BOT_TOKEN = os.environ["DISCORD_BOT_TOKEN"]
DEFAULT_CHANNEL = os.environ.get("DISCORD_CHANNEL_ID", "")

mcp = FastMCP("discord")


def _headers() -> dict:
    return {"Authorization": f"Bot {BOT_TOKEN}", "Content-Type": "application/json"}


async def _get(path: str) -> dict | list:
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(f"{DISCORD_BASE}{path}", headers=_headers())
        resp.raise_for_status()
        return resp.json()


async def _post(path: str, payload: dict) -> dict:
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.post(f"{DISCORD_BASE}{path}", headers=_headers(), json=payload)
        resp.raise_for_status()
        return resp.json()


def _discord_error(e: Exception, context: str) -> ValueError:
    if isinstance(e, httpx.HTTPStatusError):
        return ValueError(
            f"Discord API error {e.response.status_code} ({context}): {e.response.text}"
        )
    if isinstance(e, httpx.TimeoutException):
        return ValueError(f"Discord API timed out ({context})")
    raise e


@mcp.tool()
async def post_message(content: str, channel_id: str = DEFAULT_CHANNEL) -> dict:
    """Post a plain text message to a Discord channel. Returns the created message object
    including id, channel_id, and timestamp. channel_id defaults to DISCORD_CHANNEL_ID env var."""
    if not channel_id:
        raise ValueError("channel_id is required (or set DISCORD_CHANNEL_ID env var)")
    try:
        return await _post(f"/channels/{channel_id}/messages", {"content": content})
    except Exception as e:
        raise _discord_error(e, f"channel_id={channel_id}")


@mcp.tool()
async def send_embed(
    title: str,
    description: str,
    fields: list[dict],
    channel_id: str = DEFAULT_CHANNEL,
    color: int = 0x5865F2,
) -> dict:
    """Post a rich embed message to a Discord channel. Embeds support structured layout with
    named fields. Each field in `fields` must have 'name' and 'value' keys, and optionally
    'inline' (bool) to display fields side-by-side. color is an integer (e.g. 0x00FF00 for green,
    0xFF0000 for red). Use for trade summaries, standings, lineup recommendations, etc."""
    if not channel_id:
        raise ValueError("channel_id is required (or set DISCORD_CHANNEL_ID env var)")
    payload = {
        "embeds": [
            {
                "title": title,
                "description": description,
                "color": color,
                "fields": fields,
            }
        ]
    }
    try:
        return await _post(f"/channels/{channel_id}/messages", payload)
    except Exception as e:
        raise _discord_error(e, f"channel_id={channel_id}")


@mcp.tool()
async def read_messages(channel_id: str, limit: int = 10) -> list[dict]:
    """Read recent messages from a Discord channel. Returns up to `limit` messages (max 100),
    newest first. Each message includes id, content, author (username + id), and timestamp.
    Requires the bot to have Read Message History permission in the channel."""
    if limit > 100:
        raise ValueError("limit cannot exceed 100 (Discord API maximum)")
    try:
        return await _get(f"/channels/{channel_id}/messages?limit={limit}")
    except Exception as e:
        raise _discord_error(e, f"channel_id={channel_id}")


@mcp.tool()
async def list_channels(guild_id: str) -> list[dict]:
    """List all channels in a Discord server (guild). Returns channel id, name, type, and
    position. Channel type 0 = text, 2 = voice, 4 = category, 5 = announcement. Use this
    to find the correct channel_id for post_message / read_messages calls."""
    try:
        return await _get(f"/guilds/{guild_id}/channels")
    except Exception as e:
        raise _discord_error(e, f"guild_id={guild_id}")


if __name__ == "__main__":
    mcp.run()
