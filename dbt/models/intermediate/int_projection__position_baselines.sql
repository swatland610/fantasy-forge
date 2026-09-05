-- int_projection__position_baselines
-- Grain: one row per (projection_season, position) for QB/RB/WR/TE.
-- The shrink TARGETS for the projection: the recency-weighted, volume-weighted league rate for
-- each efficiency / TD / first-down / minor component, computed AS-OF each projection season.
-- A player's noisy own-rate is pulled toward these via reliability_shrink() in
-- proj_player_season_components.
--
-- SEASON-GENERALIZED (Option 1 of the V-GATE roadmap): instead of a single target year passed as
-- a var, the projection season is a COLUMN over a spine of target seasons (var projection_seasons,
-- default = the 5 backtest folds 2021-2025 + the live 2026 board). Every fold sees ONLY its own
-- past (season between projection_season-3 and projection_season-1), so a backtest fold can never
-- leak future data into its own baseline. The live 2026 board is just projection_season = 2026.
--
-- DESIGN DECISIONS (flagged per guardrails):
--   * RECENCY DECAY (same scheme as the projection): a season `lag` years before the target
--     season is weighted 1.0 / 0.667 / 0.333 for lag 1 / 2 / 3, 0 beyond. This is the 3-2-1
--     window normalized so the most-recent season (the one the fitted k's were calibrated
--     against, at 1-year lag) carries weight 1.0.
--   * VOLUME-WEIGHTED rates: each rate is sum(decay*numerator)/sum(decay*denominator), i.e.
--     the true league rate, NOT an average of per-player rates (which would over-weight
--     small-sample scrubs). Carry/target/attempt totals are the denominators.
--   * STARTERS ONLY (games_played >= 8): the baseline should reflect real NFL contributor
--     rates, not garbage-time noise. Explicit filter -- lift it to widen the pool.
--
-- NULL handling: nullif(denominator, 0) makes a rate NULL when a position never accumulates
-- that opportunity type (e.g. WR pass attempts) rather than 0/0. Surfaced, not coalesced.

{% set projection_seasons = var('projection_seasons', [2021, 2022, 2023, 2024, 2025, 2026]) %}

with season_spine as (

    -- the target seasons we build baselines for (backtest folds + live board)
    select unnest([{{ projection_seasons | join(', ') }}]) as projection_season

),

seasons as (

    -- every (target season, contributing prior season) pair, tagged with its recency decay
    select
        sp.projection_season,
        s.position,
        -- recency decay weight: 1.0 / 0.667 / 0.333 for the last three seasons, else 0
        case sp.projection_season - s.season
            when 1 then 1.0
            when 2 then 0.667
            when 3 then 0.333
            else 0.0
        end as decay,
        s.games_played,
        s.completions, s.pass_attempts, s.sacks_suffered, s.passing_yards, s.passing_tds,
        s.passing_interceptions, s.passing_first_downs, s.passing_2pt_conversions,
        s.carries, s.rushing_yards, s.rushing_tds, s.rushing_first_downs, s.rushing_2pt_conversions,
        s.rushing_fumbles_lost,
        s.receptions, s.targets, s.receiving_yards, s.receiving_tds, s.receiving_first_downs,
        s.receiving_2pt_conversions, s.receiving_fumbles_lost
    from season_spine as sp
    join {{ ref('fct_player_season_stats') }} as s
        on s.season between sp.projection_season - 3 and sp.projection_season - 1
    where s.position in ('QB', 'RB', 'WR', 'TE')
      and s.games_played >= 8

),

weighted as (

    select
        projection_season,
        position,

        -- durability anchor: recency-weighted mean games among starters
        sum(decay * games_played) / nullif(sum(decay), 0) as baseline_games,

        -- decayed opportunity denominators
        sum(decay * pass_attempts) as d_attempts,
        sum(decay * carries)       as d_carries,
        sum(decay * targets)       as d_targets,

        -- ===== PASSING rates =====
        sum(decay * completions)           / nullif(sum(decay * pass_attempts), 0) as completion_pct,
        sum(decay * passing_yards)         / nullif(sum(decay * pass_attempts), 0) as yards_per_attempt,
        sum(decay * passing_tds)           / nullif(sum(decay * pass_attempts), 0) as pass_td_rate,
        sum(decay * passing_interceptions) / nullif(sum(decay * pass_attempts), 0) as int_rate,
        sum(decay * passing_2pt_conversions) / nullif(sum(decay * pass_attempts), 0) as pass_2pt_rate,

        -- sack rate per DROPBACK (attempts + sacks): the denominator is all pass plays, not
        -- just thrown attempts. QB-only signal in practice; ~0 for other positions.
        sum(decay * sacks_suffered)
            / nullif(sum(decay * (pass_attempts + sacks_suffered)), 0) as sack_rate,

        -- ===== RUSHING rates =====
        sum(decay * rushing_yards)         / nullif(sum(decay * carries), 0) as yards_per_carry,
        sum(decay * rushing_tds)           / nullif(sum(decay * carries), 0) as rush_td_rate,
        sum(decay * rushing_first_downs)   / nullif(sum(decay * carries), 0) as rush_1d_rate,
        sum(decay * rushing_2pt_conversions) / nullif(sum(decay * carries), 0) as rush_2pt_rate,
        sum(decay * rushing_fumbles_lost)  / nullif(sum(decay * carries), 0) as rush_fumble_rate,

        -- ===== RECEIVING rates (per TARGET, so they compose with projected targets) =====
        sum(decay * receptions)            / nullif(sum(decay * targets), 0) as catch_rate,
        sum(decay * receiving_yards)       / nullif(sum(decay * targets), 0) as yards_per_target,
        sum(decay * receiving_tds)         / nullif(sum(decay * targets), 0) as rec_td_rate,
        sum(decay * receiving_first_downs) / nullif(sum(decay * targets), 0) as rec_1d_rate,
        sum(decay * receiving_2pt_conversions) / nullif(sum(decay * targets), 0) as rec_2pt_rate,
        sum(decay * receiving_fumbles_lost) / nullif(sum(decay * targets), 0) as rec_fumble_rate

    from seasons
    group by projection_season, position

)

select
    projection_season,
    position,
    baseline_games,
    completion_pct,
    yards_per_attempt,
    pass_td_rate,
    int_rate,
    pass_2pt_rate,
    sack_rate,
    yards_per_carry,
    rush_td_rate,
    rush_1d_rate,
    rush_2pt_rate,
    rush_fumble_rate,
    catch_rate,
    yards_per_target,
    rec_td_rate,
    rec_1d_rate,
    rec_2pt_rate,
    rec_fumble_rate
from weighted
