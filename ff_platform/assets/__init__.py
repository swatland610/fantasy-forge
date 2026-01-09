"""Dagster assets for the FF data platform."""

from ff_platform.assets.nfl_data import (
    # Core game data
    raw_pbp,
    raw_schedules,
    raw_officials,
    # Player/team stats
    raw_player_stats,
    raw_team_stats,
    raw_snap_counts,
    raw_participation,
    raw_injuries,
    # Advanced stats
    raw_nextgen_stats_passing,
    raw_nextgen_stats_rushing,
    raw_nextgen_stats_receiving,
    raw_pfr_advstats_passing,
    raw_pfr_advstats_rushing,
    raw_pfr_advstats_receiving,
    raw_pfr_advstats_defense,
    raw_ftn_charting,
    # Roster/personnel
    raw_rosters,
    raw_rosters_weekly,
    raw_depth_charts,
    # Reference data
    raw_teams,
    raw_players,
    raw_draft_picks,
    raw_combine,
    raw_contracts,
    raw_trades,
    # Fantasy football
    raw_ff_playerids,
    raw_ff_rankings,
    raw_ff_opportunity,
)

__all__ = [
    "raw_pbp",
    "raw_schedules",
    "raw_officials",
    "raw_player_stats",
    "raw_team_stats",
    "raw_snap_counts",
    "raw_participation",
    "raw_injuries",
    "raw_nextgen_stats_passing",
    "raw_nextgen_stats_rushing",
    "raw_nextgen_stats_receiving",
    "raw_pfr_advstats_passing",
    "raw_pfr_advstats_rushing",
    "raw_pfr_advstats_receiving",
    "raw_pfr_advstats_defense",
    "raw_ftn_charting",
    "raw_rosters",
    "raw_rosters_weekly",
    "raw_depth_charts",
    "raw_teams",
    "raw_players",
    "raw_draft_picks",
    "raw_combine",
    "raw_contracts",
    "raw_trades",
    "raw_ff_playerids",
    "raw_ff_rankings",
    "raw_ff_opportunity",
]
