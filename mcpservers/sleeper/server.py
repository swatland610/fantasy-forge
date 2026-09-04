import httpx
from mcp.server.fastmcp import FastMCP

SLEEPER_BASE = "https://api.sleeper.app/v1"

mcp = FastMCP("sleeper")


async def _get(path: str) -> dict | list:
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(f"{SLEEPER_BASE}{path}")
        resp.raise_for_status()
        return resp.json()


def _sleeper_error(e: Exception, context: str) -> ValueError:
    if isinstance(e, httpx.HTTPStatusError):
        return ValueError(f"Sleeper API error {e.response.status_code} ({context}): {e.response.text}")
    if isinstance(e, httpx.TimeoutException):
        return ValueError(f"Sleeper API timed out ({context}) — service may be temporarily unavailable")
    raise e


@mcp.tool()
async def get_user(username: str) -> dict:
    """Fetch a Sleeper user by username. Returns user_id, display_name, and avatar.
    Use the returned user_id for all subsequent user-specific calls (get_leagues, etc.)."""
    try:
        return await _get(f"/user/{username}")
    except Exception as e:
        raise _sleeper_error(e, f"username={username}")


@mcp.tool()
async def get_leagues(user_id: str, season: int) -> list[dict]:
    """Fetch all NFL fantasy leagues for a Sleeper user in a given season year.
    Returns league metadata including league_id, name, scoring settings, and roster positions.
    Use league_id from the result for roster/matchup/transaction calls."""
    try:
        return await _get(f"/user/{user_id}/leagues/nfl/{season}")
    except Exception as e:
        raise _sleeper_error(e, f"user_id={user_id}, season={season}")


@mcp.tool()
async def get_league(league_id: str) -> dict:
    """Fetch full details for a Sleeper league. Includes scoring_settings (points per stat),
    roster_positions (flex/superflex config), total_rosters, and trade/waiver rules."""
    try:
        return await _get(f"/league/{league_id}")
    except Exception as e:
        raise _sleeper_error(e, f"league_id={league_id}")


@mcp.tool()
async def get_rosters(league_id: str) -> list[dict]:
    """Fetch all rosters in a Sleeper league. Each roster includes owner_id, players (list of
    Sleeper player IDs), starters, reserve (IR), and taxi slots. Note: player IDs here are
    Sleeper-specific — join against core.dim_players.sleeper_id to map to nfl-verse player_id."""
    try:
        return await _get(f"/league/{league_id}/rosters")
    except Exception as e:
        raise _sleeper_error(e, f"league_id={league_id}")


@mcp.tool()
async def get_users_in_league(league_id: str) -> list[dict]:
    """Fetch all users (team managers) in a Sleeper league.
    Returns user_id, display_name, team_name, and avatar per user.
    Cross-reference with get_rosters via owner_id to match rosters to managers."""
    try:
        return await _get(f"/league/{league_id}/users")
    except Exception as e:
        raise _sleeper_error(e, f"league_id={league_id}")


@mcp.tool()
async def get_matchups(league_id: str, week: int) -> list[dict]:
    """Fetch matchup results for a specific week in a Sleeper league.
    Returns a list where each entry is a team's matchup slot: roster_id, matchup_id (teams with
    the same matchup_id are opponents), starters, players, and points per starter."""
    try:
        return await _get(f"/league/{league_id}/matchups/{week}")
    except Exception as e:
        raise _sleeper_error(e, f"league_id={league_id}, week={week}")


@mcp.tool()
async def get_transactions(league_id: str, week: int) -> list[dict]:
    """Fetch all transactions (waivers, free agent adds, trades) for a given week.
    Each transaction includes type (waiver/free_agent/trade), status, adds/drops (player_id -> roster_id
    maps), and draft_picks involved in trades. Returns an empty list if no activity that week."""
    try:
        return await _get(f"/league/{league_id}/transactions/{week}")
    except Exception as e:
        raise _sleeper_error(e, f"league_id={league_id}, week={week}")


@mcp.tool()
async def get_trending_players(
    sport: str = "nfl",
    trend_type: str = "add",
    hours: int = 24,
    limit: int = 25,
) -> list[dict]:
    """Fetch trending players across all Sleeper leagues. trend_type is 'add' or 'drop'.
    Returns player_id and count (number of adds/drops in the lookback window).
    Cross-reference player_id against core.dim_players.sleeper_id to get names and positions."""
    try:
        return await _get(
            f"/players/{sport}/trending/{trend_type}?lookback_hours={hours}&limit={limit}"
        )
    except Exception as e:
        raise _sleeper_error(e, f"sport={sport}, type={trend_type}")


@mcp.tool()
async def get_nfl_state() -> dict:
    """Fetch the current NFL season state from Sleeper. Returns season, week, season_type
    (pre/regular/post), and display_week. Use this to determine the current week before
    making week-specific calls like get_matchups or get_transactions."""
    try:
        return await _get("/state/nfl")
    except Exception as e:
        raise _sleeper_error(e, "nfl_state")


if __name__ == "__main__":
    mcp.run()
