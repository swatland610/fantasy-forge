-- fct_player_season_stats
-- Grain: one row per (player_id, season). Collapses the game-grain fact to a season
-- rollup -- the unit the preseason projection (V3) forecasts.
--
-- DESIGN DECISIONS (flagged per guardrails -- review these):
--   * REGULAR SEASON ONLY (season_type = 'REG'). Preseason projections forecast
--     regular-season production; NFL postseason games are not fantasy-scored. This is an
--     explicit filter, not a silent one -- lift it here if postseason should be included.
--   * Mid-season team changes collapse to ONE row; team/position are the player's LAST
--     by week (arg_max(_, week)). Stat totals are summed across all stints.
--   * games_played = count(distinct week): a traded player who plays one game in a week
--     still counts as one game.
--
-- NULL handling (surfaced, never coalesced):
--   * Efficiency rates divide by an opportunity count via nullif(denominator, 0), so a
--     player with zero carries/targets/attempts gets a NULL rate (undefined), NOT a
--     misleading 0. NULL here means "no opportunity," which is data.
--   * EPA columns are NULL for game-stints with no plays of that type; sum() ignores
--     NULLs, so a pure WR's season passing_epa is NULL (correct -- threw no passes).
--
-- APPROXIMATIONS (flagged for V3 / feature-layer refinement):
--   * avg_* share columns (target_share, air_yards_share, wopr, offense_pct) are the
--     MEAN of per-GAME shares, not a true season share (player season total / team season
--     total) -- this fact has no team-season denominator. Good enough as a stability-test
--     proxy; refine in the feature layer if the V-GATE shows it matters.

with game_stats as (

    select *
    from {{ ref('fct_player_game_stats') }}
    where season_type = 'REG'

),

season_rollup as (

    select
        -- ===== IDENTIFIERS / GRAIN =====
        player_id,
        season,

        -- ===== PLAYER INFO (last team/position by week) =====
        arg_max(position, week) as position,
        arg_max(team, week)     as team,

        -- ===== AVAILABILITY =====
        count(distinct week)    as games_played,

        -- ===== PASSING (season totals) =====
        sum(completions)              as completions,
        sum(pass_attempts)            as pass_attempts,
        sum(passing_yards)            as passing_yards,
        sum(passing_tds)              as passing_tds,
        sum(passing_interceptions)    as passing_interceptions,
        sum(sacks_suffered)           as sacks_suffered,
        sum(passing_air_yards)        as passing_air_yards,
        sum(passing_first_downs)      as passing_first_downs,
        sum(passing_2pt_conversions)  as passing_2pt_conversions,
        sum(passing_epa)              as passing_epa,

        -- ===== RUSHING (season totals) =====
        sum(carries)                  as carries,
        sum(rushing_yards)            as rushing_yards,
        sum(rushing_tds)              as rushing_tds,
        sum(rushing_fumbles_lost)     as rushing_fumbles_lost,
        sum(rushing_first_downs)      as rushing_first_downs,
        sum(rushing_2pt_conversions)  as rushing_2pt_conversions,
        sum(rushing_epa)              as rushing_epa,

        -- ===== RECEIVING (season totals) =====
        sum(receptions)               as receptions,
        sum(targets)                  as targets,
        sum(receiving_yards)          as receiving_yards,
        sum(receiving_tds)            as receiving_tds,
        sum(receiving_fumbles_lost)   as receiving_fumbles_lost,
        sum(receiving_air_yards)      as receiving_air_yards,
        sum(receiving_first_downs)    as receiving_first_downs,
        sum(receiving_2pt_conversions) as receiving_2pt_conversions,
        sum(receiving_epa)            as receiving_epa,

        -- ===== SNAPS =====
        sum(offense_snaps)            as offense_snaps,

        -- ===== SHARE METRICS (mean of per-game shares -- see header) =====
        avg(offense_pct)              as avg_offense_pct,
        avg(target_share)             as avg_target_share,
        avg(air_yards_share)          as avg_air_yards_share,
        avg(wopr)                     as avg_wopr

    from game_stats
    group by player_id, season

)

-- Final select: season totals pass through; per-game and per-opportunity rates derived
-- here (explicit column list -- no select *).
select
    player_id,
    season,
    position,
    team,
    games_played,

    -- passing totals
    completions,
    pass_attempts,
    passing_yards,
    passing_tds,
    passing_interceptions,
    sacks_suffered,
    passing_air_yards,
    passing_first_downs,
    passing_2pt_conversions,
    passing_epa,

    -- rushing totals
    carries,
    rushing_yards,
    rushing_tds,
    rushing_fumbles_lost,
    rushing_first_downs,
    rushing_2pt_conversions,
    rushing_epa,

    -- receiving totals
    receptions,
    targets,
    receiving_yards,
    receiving_tds,
    receiving_fumbles_lost,
    receiving_air_yards,
    receiving_first_downs,
    receiving_2pt_conversions,
    receiving_epa,

    -- snaps
    offense_snaps,

    -- ===== PER-GAME VOLUME (the stable opportunity signal V3 leans on) =====
    pass_attempts  / games_played as pass_attempts_per_game,
    carries        / games_played as carries_per_game,
    targets        / games_played as targets_per_game,
    receptions     / games_played as receptions_per_game,
    offense_snaps  / games_played as offense_snaps_per_game,

    -- ===== PER-OPPORTUNITY EFFICIENCY (NULL when no opportunity -- see header) =====
    completions    / nullif(pass_attempts, 0) as completion_pct,
    passing_yards  / nullif(pass_attempts, 0) as yards_per_attempt,
    rushing_yards  / nullif(carries, 0)       as yards_per_carry,
    receiving_yards / nullif(targets, 0)      as yards_per_target,
    receptions     / nullif(targets, 0)       as catch_rate,

    -- share metrics (mean of per-game shares)
    avg_offense_pct,
    avg_target_share,
    avg_air_yards_share,
    avg_wopr

from season_rollup
