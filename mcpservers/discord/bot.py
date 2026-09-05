"""Discord bot with slash commands for fantasy football queries.

Run separately from the MCP server:
    uv run python mcp/discord/bot.py

Required env vars:
    DISCORD_BOT_TOKEN   — bot token from Discord Developer Portal
    DISCORD_GUILD_ID    — (dev) guild ID for instant slash command sync; omit for global sync
    DUCKDB_PATH         — path to the DuckDB file (default: data/ff_platform.duckdb)
"""

import os

import discord
import duckdb
import httpx
from discord import app_commands

GUILD_ID = int(os.environ["DISCORD_GUILD_ID"]) if os.environ.get("DISCORD_GUILD_ID") else None
DB_PATH = os.environ.get("DUCKDB_PATH", "data/ff_platform.duckdb")
SLEEPER_BASE = "https://api.sleeper.app/v1"

intents = discord.Intents.default()
client = discord.Client(intents=intents)
tree = app_commands.CommandTree(client)


def query_db(sql: str, params: tuple = ()) -> list[dict]:
    con = duckdb.connect(DB_PATH, read_only=True)
    try:
        result = con.execute(sql, list(params))
        rows = result.fetchall()
        cols = [d[0] for d in result.description]
        return [dict(zip(cols, row)) for row in rows]
    finally:
        con.close()


def make_embed(title: str, description: str, rows: list[dict], color: int = 0x5865F2) -> discord.Embed:
    embed = discord.Embed(title=title, description=description, color=color)
    for row in rows:
        name = row.pop("_field_name", "—")
        value = "\n".join(f"**{k}:** {v}" for k, v in row.items() if v is not None)
        embed.add_field(name=name, value=value or "—", inline=False)
    return embed


@client.event
async def on_ready():
    if GUILD_ID:
        guild = discord.Object(id=GUILD_ID)
        tree.copy_global_to(guild=guild)
        await tree.sync(guild=guild)
        print(f"Synced slash commands to guild {GUILD_ID}")
    else:
        await tree.sync()
        print("Synced slash commands globally (may take up to 1 hour to propagate)")
    print(f"Bot ready as {client.user}")


@tree.command(name="lineup", description="Top players by VORP for a position")
@app_commands.describe(
    position="Position (QB/RB/WR/TE/K)",
    league_id="League ID (default: boc)",
    season="Projection season year",
)
async def lineup(
    interaction: discord.Interaction,
    position: str = "QB",
    league_id: str = "boc",
    season: int = 2026,
):
    await interaction.response.defer()
    rows = query_db(
        """
        SELECT
            v.position_rank || '. ' || p.display_name AS _field_name,
            p.team AS Team,
            ROUND(v.projected_points, 1) AS "Proj Pts",
            ROUND(v.vorp, 1) AS VORP
        FROM analytics.player_values v
        JOIN core.dim_players p ON p.player_id = v.player_id
        WHERE v.position = ?
          AND v.league_id = ?
          AND v.projection_season = ?
        ORDER BY v.position_rank
        LIMIT 10
        """,
        (position.upper(), league_id, season),
    )
    if not rows:
        await interaction.followup.send(
            f"No data found for {position.upper()} in league `{league_id}` season {season}."
        )
        return
    embed = make_embed(
        title=f"Top {position.upper()}s — {season} ({league_id})",
        description=f"Ranked by VORP (value over replacement), projection season {season}",
        rows=rows,
        color=0x00B300,
    )
    await interaction.followup.send(embed=embed)


@tree.command(name="trade-value", description="Look up a player's projected value and VORP")
@app_commands.describe(
    player_name="Player name (partial match OK)",
    season="Projection season year",
)
async def trade_value(
    interaction: discord.Interaction,
    player_name: str,
    season: int = 2026,
):
    await interaction.response.defer()
    rows = query_db(
        """
        SELECT
            p.display_name AS _field_name,
            p.position AS Position,
            p.team AS Team,
            v.league_id AS League,
            ROUND(v.projected_points, 1) AS "Proj Pts",
            ROUND(v.vorp, 1) AS VORP,
            v.overall_rank AS "Overall Rank",
            v.position_rank AS "Position Rank"
        FROM analytics.player_values v
        JOIN core.dim_players p ON p.player_id = v.player_id
        WHERE lower(p.display_name) LIKE lower(?)
          AND v.projection_season = ?
        ORDER BY v.overall_rank
        LIMIT 5
        """,
        (f"%{player_name}%", season),
    )
    if not rows:
        await interaction.followup.send(
            f"No players found matching `{player_name}` for season {season}."
        )
        return
    embed = make_embed(
        title=f'Trade Value: "{player_name}" ({season})',
        description="Projected points and VORP from local analytics model",
        rows=rows,
        color=0x5865F2,
    )
    await interaction.followup.send(embed=embed)


@tree.command(name="waiver", description="Trending waiver wire adds from Sleeper")
@app_commands.describe(
    hours="Lookback hours (default: 24)",
    limit="Number of players to show (default: 10)",
)
async def waiver(
    interaction: discord.Interaction,
    hours: int = 24,
    limit: int = 10,
):
    await interaction.response.defer()
    async with httpx.AsyncClient(timeout=10.0) as http:
        resp = await http.get(
            f"{SLEEPER_BASE}/players/nfl/trending/add",
            params={"lookback_hours": hours, "limit": limit},
        )
        resp.raise_for_status()
        trending = resp.json()

    sleeper_ids = [str(t["player_id"]) for t in trending]
    if not sleeper_ids:
        await interaction.followup.send("No trending players found.")
        return

    # dim_players.sleeper_id is BIGINT, but Sleeper uses the team abbreviation as the
    # player_id for team defenses ("SF", "NE"), and those appear in the trending feed.
    # Comparing them against a BIGINT column raises ConversionException mid-command --
    # after defer(), so the user just sees a hung interaction. Cast the column instead of
    # the parameters so defenses simply miss the lookup rather than killing the query.
    placeholders = ", ".join(["?" for _ in sleeper_ids])
    enriched = query_db(
        f"""
        SELECT sleeper_id, display_name, position, team
        FROM core.dim_players
        WHERE CAST(sleeper_id AS VARCHAR) IN ({placeholders})
        """,
        tuple(sleeper_ids),
    )
    # keys must be str to match the str(player_id) lookup below -- DuckDB returns BIGINT
    # as Python int, so keying on the raw value made every lookup miss silently
    by_sleeper_id = {str(r["sleeper_id"]): r for r in enriched}

    rows = []
    for i, t in enumerate(trending[:limit], 1):
        sid = str(t["player_id"])
        player = by_sleeper_id.get(sid, {})
        rows.append({
            "_field_name": f"{i}. {player.get('display_name', sid)}",
            "Position": player.get("position", "—"),
            "Team": player.get("team", "—"),
            "Adds": t.get("count", "—"),
        })

    embed = make_embed(
        title=f"Trending Waiver Adds (last {hours}h)",
        description=f"Top {limit} most-added players across Sleeper leagues",
        rows=rows,
        color=0xFF8C00,
    )
    await interaction.followup.send(embed=embed)


@tree.command(name="standings", description="Live league standings from Sleeper")
@app_commands.describe(league_id="Sleeper league ID")
async def standings(interaction: discord.Interaction, league_id: str):
    await interaction.response.defer()
    async with httpx.AsyncClient(timeout=10.0) as http:
        rosters_resp = await http.get(f"{SLEEPER_BASE}/league/{league_id}/rosters")
        users_resp = await http.get(f"{SLEEPER_BASE}/league/{league_id}/users")
        rosters_resp.raise_for_status()
        users_resp.raise_for_status()

    rosters = rosters_resp.json()
    users = users_resp.json()
    user_map = {u["user_id"]: u.get("display_name", u["user_id"]) for u in users}

    sorted_rosters = sorted(
        rosters,
        key=lambda r: (
            -(r.get("settings", {}).get("wins", 0)),
            r.get("settings", {}).get("losses", 0),
            -(r.get("settings", {}).get("fpts", 0) + r.get("settings", {}).get("fpts_decimal", 0) / 100),
        ),
    )

    rows = []
    for i, r in enumerate(sorted_rosters, 1):
        settings = r.get("settings", {})
        wins = settings.get("wins", 0)
        losses = settings.get("losses", 0)
        fpts = settings.get("fpts", 0) + settings.get("fpts_decimal", 0) / 100
        owner = user_map.get(r.get("owner_id", ""), "Unknown")
        rows.append({
            "_field_name": f"{i}. {owner}",
            "Record": f"{wins}-{losses}",
            "Points For": round(fpts, 2),
        })

    embed = make_embed(
        title=f"Standings — League {league_id}",
        description="Live standings from Sleeper (wins → losses → points for)",
        rows=rows,
        color=0x9B59B6,
    )
    await interaction.followup.send(embed=embed)


if __name__ == "__main__":
    token = os.environ.get("DISCORD_BOT_TOKEN")
    if not token:
        raise RuntimeError("DISCORD_BOT_TOKEN env var is required")
    client.run(token)
