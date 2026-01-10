"""NFL data ingestion assets using nflreadpy.

All assets use full reload (seasons=True) for simplicity.
Can add partitioned/incremental logic later if needed.
"""

import nflreadpy as nfl
from dagster import AssetExecutionContext, asset

from ff_platform.resources import DuckDBResource

# =============================================================================
# Core game data
# =============================================================================


@asset(group_name="raw")
def raw_pbp(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Play-by-play data for all seasons."""
    context.log.info("Loading play-by-play data for all seasons")
    df = nfl.load_pbp(seasons=True)
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="pbp")


@asset(group_name="raw")
def raw_schedules(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Game schedules for all seasons."""
    context.log.info("Loading schedules for all seasons")
    df = nfl.load_schedules(seasons=True)
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="schedules")


@asset(group_name="raw")
def raw_officials(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Game officials data."""
    context.log.info("Loading officials data")
    df = nfl.load_officials(seasons=True)
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="officials")


# =============================================================================
# Player/team stats
# =============================================================================


@asset(group_name="raw")
def raw_player_stats(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Weekly player stats for all seasons."""
    context.log.info("Loading player stats for all seasons")
    df = nfl.load_player_stats(seasons=True)
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="player_stats")


@asset(group_name="raw")
def raw_team_stats(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Team stats for all seasons."""
    context.log.info("Loading team stats for all seasons")
    df = nfl.load_team_stats(seasons=True)
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="team_stats")


@asset(group_name="raw")
def raw_snap_counts(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Snap count data for all seasons."""
    context.log.info("Loading snap counts for all seasons")
    df = nfl.load_snap_counts(seasons=True)
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="snap_counts")


@asset(group_name="raw")
def raw_participation(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Play participation data for all seasons."""
    context.log.info("Loading participation data for all seasons")
    df = nfl.load_participation(seasons=True)
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="participation")


@asset(group_name="raw")
def raw_injuries(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Injury report data for all seasons."""
    context.log.info("Loading injuries for all seasons")
    df = nfl.load_injuries(seasons=[i for i in range(2009, 2025)])
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="injuries")


# =============================================================================
# Advanced stats
# =============================================================================


@asset(group_name="raw")
def raw_nextgen_stats_passing(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Next Gen Stats - passing."""
    context.log.info("Loading nextgen passing stats for all seasons")
    df = nfl.load_nextgen_stats(seasons=True, stat_type="passing")
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="nextgen_stats_passing")


@asset(group_name="raw")
def raw_nextgen_stats_rushing(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Next Gen Stats - rushing."""
    context.log.info("Loading nextgen rushing stats for all seasons")
    df = nfl.load_nextgen_stats(seasons=True, stat_type="rushing")
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="nextgen_stats_rushing")


@asset(group_name="raw")
def raw_nextgen_stats_receiving(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Next Gen Stats - receiving."""
    context.log.info("Loading nextgen receiving stats for all seasons")
    df = nfl.load_nextgen_stats(seasons=True, stat_type="receiving")
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="nextgen_stats_receiving")


@asset(group_name="raw")
def raw_pfr_advstats_passing(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Pro Football Reference advanced stats - passing."""
    context.log.info("Loading PFR passing stats for all seasons")
    df = nfl.load_pfr_advstats(seasons=True, stat_type="pass")
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="pfr_advstats_passing")


@asset(group_name="raw")
def raw_pfr_advstats_rushing(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Pro Football Reference advanced stats - rushing."""
    context.log.info("Loading PFR rushing stats for all seasons")
    df = nfl.load_pfr_advstats(seasons=True, stat_type="rush")
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="pfr_advstats_rushing")


@asset(group_name="raw")
def raw_pfr_advstats_receiving(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Pro Football Reference advanced stats - receiving."""
    context.log.info("Loading PFR receiving stats for all seasons")
    df = nfl.load_pfr_advstats(seasons=True, stat_type="rec")
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="pfr_advstats_receiving")


@asset(group_name="raw")
def raw_pfr_advstats_defense(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Pro Football Reference advanced stats - defense."""
    context.log.info("Loading PFR defense stats for all seasons")
    df = nfl.load_pfr_advstats(seasons=True, stat_type="def")
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="pfr_advstats_defense")


@asset(group_name="raw")
def raw_ftn_charting(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """FTN charting data for all seasons."""
    context.log.info("Loading FTN charting data for all seasons")
    df = nfl.load_ftn_charting(seasons=True)
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="ftn_charting")


# =============================================================================
# Roster/personnel data
# =============================================================================


@asset(group_name="raw")
def raw_rosters(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Season rosters for all seasons."""
    context.log.info("Loading roster data for all seasons")
    df = nfl.load_rosters(seasons=True)
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="rosters")


@asset(group_name="raw")
def raw_rosters_weekly(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Weekly roster data for all seasons."""
    context.log.info("Loading weekly rosters for all seasons")
    df = nfl.load_rosters_weekly(seasons=True)
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="rosters_weekly")


@asset(group_name="raw")
def raw_depth_charts(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Depth chart data for all seasons."""
    context.log.info("Loading depth charts for all seasons")
    df = nfl.load_depth_charts(seasons=True)
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="depth_charts")


# =============================================================================
# Reference/lookup data (no seasons param)
# =============================================================================


@asset(group_name="raw")
def raw_teams(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Team reference data."""
    context.log.info("Loading teams reference data")
    df = nfl.load_teams()
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="teams")


@asset(group_name="raw")
def raw_players(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Player reference data."""
    context.log.info("Loading players reference data")
    df = nfl.load_players()
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="players")


@asset(group_name="raw")
def raw_draft_picks(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Historical draft picks."""
    context.log.info("Loading draft picks data")
    df = nfl.load_draft_picks()
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="draft_picks")


@asset(group_name="raw")
def raw_combine(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """NFL combine results."""
    context.log.info("Loading combine data")
    df = nfl.load_combine()
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="combine")


@asset(group_name="raw")
def raw_contracts(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Player contract data."""
    context.log.info("Loading contracts data")
    df = nfl.load_contracts()
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="contracts")


@asset(group_name="raw")
def raw_trades(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Historical trade data."""
    context.log.info("Loading trades data")
    df = nfl.load_trades()
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="trades")


# =============================================================================
# Fantasy football specific
# =============================================================================


@asset(group_name="raw")
def raw_ff_playerids(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Fantasy football player ID mappings."""
    context.log.info("Loading FF player IDs")
    df = nfl.load_ff_playerids()
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="ff_playerids")


@asset(group_name="raw")
def raw_ff_rankings(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Fantasy football rankings for all seasons."""
    context.log.info("Loading FF rankings for all seasons")
    df = nfl.load_ff_rankings(type="all")
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="ff_rankings")


@asset(group_name="raw")
def raw_ff_opportunity(context: AssetExecutionContext, duckdb: DuckDBResource) -> None:
    """Fantasy football opportunity data for all seasons."""
    context.log.info("Loading FF opportunity for all seasons")
    df = nfl.load_ff_opportunity(seasons=True)
    context.log.info(f"Loaded {len(df)} records")
    duckdb.load_df(df, schema="raw", table="ff_opportunity")
