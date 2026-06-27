-- fct_fantasy_points
-- Grain: one row per (player_id, season, week, season_type, format_name).
-- Scores historical game-level component stats against the scoring_rules seed.
-- Scoring is linear in counting stats, so these per-game points roll up to season
-- totals by simple summation (consumed by fct_player_season_stats in V1).
--
-- NULL handling: every scorable column in fct_player_game_stats is 0-filled
-- (verified 2026-05-31: 0 NULLs across 164,780 rows), so UNPIVOT drops nothing and no
-- coalescing is applied. If that ever changes, UNPIVOT's default NULL-exclusion would
-- silently drop stats -- guard upstream with not_null tests on the source columns.
--
-- Format notes:
--   * 'ppfd' scores rushing/receiving first downs at +1 and pays 0 for receptions.
--   * passing_first_downs is intentionally never scored (would inflate QBs ~20+ pts/game).

with components as (

    select
        player_id,
        season,
        week,
        season_type,
        passing_yards,
        passing_tds,
        passing_interceptions,
        passing_2pt_conversions,
        rushing_yards,
        rushing_tds,
        rushing_2pt_conversions,
        rushing_fumbles_lost,
        rushing_first_downs,
        receptions,
        receiving_yards,
        receiving_tds,
        receiving_2pt_conversions,
        receiving_fumbles_lost,
        receiving_first_downs
    from {{ ref('fct_player_game_stats') }}

),

stats_long as (

    -- melt wide component columns into (stat_name, stat_value) long form
    unpivot components
    on
        passing_yards,
        passing_tds,
        passing_interceptions,
        passing_2pt_conversions,
        rushing_yards,
        rushing_tds,
        rushing_2pt_conversions,
        rushing_fumbles_lost,
        rushing_first_downs,
        receptions,
        receiving_yards,
        receiving_tds,
        receiving_2pt_conversions,
        receiving_fumbles_lost,
        receiving_first_downs
    into
        name stat_name
        value stat_value

),

scored as (

    -- inner join keeps only stats priced in a given format; unpriced stats contribute 0
    select
        stats_long.player_id,
        stats_long.season,
        stats_long.week,
        stats_long.season_type,
        scoring_rules.format_name,
        sum(stats_long.stat_value * scoring_rules.points_per) as fantasy_points
    from stats_long
    inner join {{ ref('scoring_rules') }} as scoring_rules
        using (stat_name)
    group by 1, 2, 3, 4, 5

)

select
    player_id,
    season,
    week,
    season_type,
    format_name,
    fantasy_points
from scored
