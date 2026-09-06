-- proj_player_season_components
-- Grain: one row per (projection_season, player_id) -- returning players with history in each
-- target season's 3-season window.
-- Phase V3 of the projections roadmap: a deliberately simple, transparent projection of every
-- SCORED counting-stat component for the target season, so the scoring layer (V4) can price it
-- under any format. Methodology: docs/reliability-weighted-shrinkage.md.
--
-- SEASON-GENERALIZED (Option 1 of the V-GATE roadmap): the projection season is a COLUMN over a
-- spine of target seasons (var projection_seasons, default = the 5 backtest folds 2021-2025 + the
-- live 2026 board), NOT a single var-passed year. This is the single projection ENGINE: the live
-- board is just projection_season = 2026; each backtest fold is projection_season = 2021..2025,
-- scored against contemporaneous ECR downstream. One source of truth, so the backtest validates
-- the exact code that builds the real board. Every fold windows strictly on its own past
-- (season between projection_season-3 and projection_season-1) -> no look-ahead leakage.
--
-- THE METHOD (per component):
--   1. OPPORTUNITY is sticky (V-GATE measured R ~ 0.6-0.8), so per-game volume
--      (carries/targets/attempts per game) is RECENCY-WEIGHTED across the last 3 seasons and
--      leaned on directly -- NOT shrunk toward a position mean.
--   2. projected_games is recency-weighted, reliability-shrunk toward the position durability
--      anchor via reliability_shrink() with a fitted k (durability has real but modest YoY
--      signal, R ~ 0.39-0.64 by position) -- see the projected_games column note below.
--   3. EFFICIENCY / TD / first-down RATES are noisy, so the player's recency-weighted own-rate
--      is pulled toward the position baseline via reliability_shrink() with the fitted k's
--      (seed: shrinkage_constants). TD rates have huge k -> projected TDs ~ volume x league rate
--      (the chosen V3 "volume x league-rate" TD approach; air-yards/goal-line proxy is a v2 item).
--   4. ASSEMBLE: season total = projected_games x projected_per_game_volume x shrunk_rate.
--
-- RECENCY DECAY: a season `lag` years before the target is weighted 1.0 / 0.667 / 0.333 for
--   lag 1 / 2 / 3 (3-2-1 normalized to the most-recent season, which is the 1-year lag the k's
--   were calibrated at).
--
-- NULL handling (surfaced, not coalesced): observed rates use nullif(denominator, 0); when a
--   player has no opportunity of a type the rate is NULL and reliability_shrink() falls cleanly
--   to the position baseline (the documented n->0 limit). Components 2pt/fumbles have no fitted
--   k -> projected as projected_volume x league baseline rate (volume expectation only; these
--   carry no per-player signal and are flagged minor).
--
-- SACKS (sacks_suffered): a QB-only scored penalty in superflex formats that price it (e.g. the
--   'boc' league: -1/sack). Modeled as a rate per DROPBACK (pass_attempts + sacks) -- a real
--   QB skill (season N->N+1 R~0.49, fit 2026-06-03) -- reliability-shrunk with its own fitted k
--   (only a QB row exists in shrinkage_constants). Volume base is projected dropbacks, NOT
--   projected pass attempts, so the rate's denominator matches. Non-QBs carry ~0 projected
--   dropbacks -> ~0 projected sacks (no special-casing; same volume x rate machinery).
--
-- SCOPE CUTS (V3, deliberate): no aging curve, no role-change/depth-chart blending, no rookie
--   sub-model. Rookies / no-history players are absent here by construction (they have no window
--   rows); thin-history returners are flagged is_projection_low_confidence, not faked. Kickers
--   are excluded (no scored components in scoring_rules). 2pt/fumble/first-down minor rates are
--   league-rate driven. All fitted shrinkage k's (including durability_games as of 2026-09-05)
--   come from scripts/fit_durability_shrinkage.py / the V-GATE stability analysis, not guesses.

{% set projection_seasons = var('projection_seasons', [2021, 2022, 2023, 2024, 2025, 2026]) %}

with season_spine as (

    -- the target seasons we project (backtest folds + live board)
    select unnest([{{ projection_seasons | join(', ') }}]) as projection_season

),

window_seasons as (

    -- (target season, contributing prior season) pairs in the 3-year window, tagged with decay
    select
        sp.projection_season,
        s.player_id,
        s.season,
        s.position,
        s.team,
        case sp.projection_season - s.season
            when 1 then 1.0
            when 2 then 0.667
            when 3 then 0.333
            else 0.0
        end as decay,
        s.games_played,
        s.completions, s.pass_attempts, s.sacks_suffered, s.passing_yards, s.passing_tds,
        s.passing_interceptions, s.passing_2pt_conversions,
        s.carries, s.rushing_yards, s.rushing_tds, s.rushing_first_downs, s.rushing_2pt_conversions,
        s.rushing_fumbles_lost,
        s.receptions, s.targets, s.receiving_yards, s.receiving_tds, s.receiving_first_downs,
        s.receiving_2pt_conversions, s.receiving_fumbles_lost
    from season_spine as sp
    join {{ ref('fct_player_season_stats') }} as s
        on s.season between sp.projection_season - 3 and sp.projection_season - 1
    where s.position in ('QB', 'RB', 'WR', 'TE')

),

agg as (

    -- collapse to one row per (projection_season, player): decay-weighted sums + confidence inputs
    select
        projection_season,
        player_id,
        arg_max(position, season) as position,   -- most recent position in window
        arg_max(team, season)     as team,        -- most recent team in window
        count(distinct season)    as seasons_of_history,
        max(case when season = projection_season - 1 then 1 else 0 end) as played_prev_season,

        sum(decay)                as w_total,
        sum(decay * games_played) as d_games,

        -- decayed opportunity denominators (also the n_eff for each rate's shrinkage)
        sum(decay * pass_attempts) as d_attempts,
        sum(decay * carries)       as d_carries,
        sum(decay * targets)       as d_targets,

        -- decayed numerators
        sum(decay * sacks_suffered)          as d_sacks,
        sum(decay * completions)             as d_completions,
        sum(decay * passing_yards)           as d_pass_yards,
        sum(decay * passing_tds)             as d_pass_tds,
        sum(decay * passing_interceptions)   as d_pass_int,
        sum(decay * rushing_yards)           as d_rush_yards,
        sum(decay * rushing_tds)             as d_rush_tds,
        sum(decay * rushing_first_downs)     as d_rush_1d,
        sum(decay * receptions)              as d_receptions,
        sum(decay * receiving_yards)         as d_rec_yards,
        sum(decay * receiving_tds)           as d_rec_tds,
        sum(decay * receiving_first_downs)   as d_rec_1d
    from window_seasons
    group by projection_season, player_id

),

k_wide as (

    -- pivot the (position, component) shrinkage seed to one row per position
    select
        position,
        max(k) filter (where component = 'completion_pct')    as k_comp,
        max(k) filter (where component = 'yards_per_attempt') as k_ya,
        max(k) filter (where component = 'pass_td_rate')      as k_pass_td,
        max(k) filter (where component = 'int_rate')          as k_int,
        max(k) filter (where component = 'sack_rate')         as k_sack,
        max(k) filter (where component = 'yards_per_carry')   as k_ypc,
        max(k) filter (where component = 'rush_td_rate')      as k_rush_td,
        max(k) filter (where component = 'rush_1d_rate')      as k_rush_1d,
        max(k) filter (where component = 'catch_rate')        as k_catch,
        max(k) filter (where component = 'yards_per_target')  as k_ypt,
        max(k) filter (where component = 'rec_td_rate')       as k_rec_td,
        max(k) filter (where component = 'rec_1d_rate')       as k_rec_1d,
        max(k) filter (where component = 'durability_games')  as k_durability
    from {{ ref('shrinkage_constants') }}
    group by position

),

derived as (

    -- projected volumes, observed (decay-weighted) rates, and the joined baseline + k inputs
    select
        agg.projection_season,
        agg.player_id,
        agg.position,
        agg.team,
        agg.seasons_of_history,
        agg.played_prev_season,

        -- projected games: reliability-weighted blend of the player's own decay-weighted
        -- trailing average (agg.d_games / agg.w_total) toward the position durability anchor
        -- (b.baseline_games, starters-only per int_projection__position_baselines), capped at
        -- a 17-game season.
        --
        -- FIT 2026-09-05 (scripts/fit_durability_shrinkage.py, see shrinkage_constants seed for
        -- the k/R/n_typ per position): n = agg.w_total, the decayed SEASON-count -- the same
        -- role d_carries/d_attempts/d_targets play for every other shrunk rate here (n is
        -- always the decayed denominator underlying the observed ratio). R was measured by
        -- correlating this exact trailing average against a player's ACTUAL held-out season
        -- games, replicating the model's own windowing -- not guessed.
        --
        -- REPLACES a prior fixed 0.75/0.25 blend, measured to inflate short-history players
        -- toward the starter-only baseline (a 3-game player pulled toward players who by
        -- definition played 8+) while under-trusting proven full-history durable players
        -- relative to what their own record supports. This fix makes the weight scale with
        -- how much trailing history exists (agg.w_total, 0 to 2.0), rather than being flat
        -- for every player regardless of evidence.
        --
        -- WHAT THIS DOES NOT FIX: a genuinely short recent season (real missed time) still
        -- pulls the trailing average down -- that's real signal properly reflected, not a
        -- shrinkage bug. E.g. an 8-game season two years running still projects below-average
        -- games; this fix corrects HOW MUCH we trust a player's own record given their amount
        -- of history, not what that record itself says happened.
        least(
            17.0,
            {{ reliability_shrink(
                'agg.d_games / nullif(agg.w_total, 0)',
                'b.baseline_games',
                'agg.w_total',
                'k.k_durability'
            ) }}
        ) as projected_games,

        -- projected per-game opportunity (games-weighted; sticky -> used directly, not shrunk)
        agg.d_attempts / nullif(agg.d_games, 0) as attempts_per_game,
        (agg.d_attempts + agg.d_sacks) / nullif(agg.d_games, 0) as dropbacks_per_game,
        agg.d_carries  / nullif(agg.d_games, 0) as carries_per_game,
        agg.d_targets  / nullif(agg.d_games, 0) as targets_per_game,

        -- n_eff for shrinkage = decayed opportunity counts
        agg.d_attempts as n_attempts,
        agg.d_attempts + agg.d_sacks as n_dropbacks,
        agg.d_carries  as n_carries,
        agg.d_targets  as n_targets,

        -- observed (decay-weighted) own rates; NULL when no opportunity (surfaced)
        agg.d_completions / nullif(agg.d_attempts, 0) as obs_comp,
        agg.d_pass_yards  / nullif(agg.d_attempts, 0) as obs_ya,
        agg.d_pass_tds    / nullif(agg.d_attempts, 0) as obs_pass_td,
        agg.d_pass_int    / nullif(agg.d_attempts, 0) as obs_int,
        agg.d_sacks       / nullif(agg.d_attempts + agg.d_sacks, 0) as obs_sack_rate,
        agg.d_rush_yards  / nullif(agg.d_carries, 0)  as obs_ypc,
        agg.d_rush_tds    / nullif(agg.d_carries, 0)  as obs_rush_td,
        agg.d_rush_1d     / nullif(agg.d_carries, 0)  as obs_rush_1d,
        agg.d_receptions  / nullif(agg.d_targets, 0)  as obs_catch,
        agg.d_rec_yards   / nullif(agg.d_targets, 0)  as obs_ypt,
        agg.d_rec_tds     / nullif(agg.d_targets, 0)  as obs_rec_td,
        agg.d_rec_1d      / nullif(agg.d_targets, 0)  as obs_rec_1d,

        -- baseline rates (shrink targets) + minor (unshrunk) league rates
        b.completion_pct, b.yards_per_attempt, b.pass_td_rate, b.int_rate, b.sack_rate, b.pass_2pt_rate,
        b.yards_per_carry, b.rush_td_rate, b.rush_1d_rate, b.rush_2pt_rate, b.rush_fumble_rate,
        b.catch_rate, b.yards_per_target, b.rec_td_rate, b.rec_1d_rate, b.rec_2pt_rate,
        b.rec_fumble_rate,

        -- fitted shrinkage constants for this position
        k.k_comp, k.k_ya, k.k_pass_td, k.k_int, k.k_sack,
        k.k_ypc, k.k_rush_td, k.k_rush_1d,
        k.k_catch, k.k_ypt, k.k_rec_td, k.k_rec_1d
    from agg
    join {{ ref('int_projection__position_baselines') }} as b
        using (projection_season, position)
    left join k_wide as k using (position)

),

assembled as (

    select
        projection_season,
        player_id,
        position,
        team,
        seasons_of_history,
        projected_games,

        -- a thin or stale history is flagged, not hidden (see header scope note)
        (seasons_of_history = 1 or played_prev_season = 0) as is_projection_low_confidence,

        -- projected season opportunity volume
        projected_games * attempts_per_game  as proj_pass_attempts,
        projected_games * dropbacks_per_game as proj_dropbacks,
        projected_games * carries_per_game   as proj_carries,
        projected_games * targets_per_game   as proj_targets,

        -- shrunk rates (carried out for transparency / debugging)
        {{ reliability_shrink('obs_comp',    'completion_pct',    'n_attempts', 'k_comp') }}    as proj_completion_pct,
        {{ reliability_shrink('obs_ya',      'yards_per_attempt', 'n_attempts', 'k_ya') }}      as proj_yards_per_attempt,
        {{ reliability_shrink('obs_pass_td', 'pass_td_rate',      'n_attempts', 'k_pass_td') }} as proj_pass_td_rate,
        {{ reliability_shrink('obs_int',     'int_rate',          'n_attempts',  'k_int') }}     as proj_int_rate,
        {{ reliability_shrink('obs_sack_rate', 'sack_rate',       'n_dropbacks', 'k_sack') }}   as proj_sack_rate,
        {{ reliability_shrink('obs_ypc',     'yards_per_carry',   'n_carries',  'k_ypc') }}     as proj_yards_per_carry,
        {{ reliability_shrink('obs_rush_td', 'rush_td_rate',      'n_carries',  'k_rush_td') }} as proj_rush_td_rate,
        {{ reliability_shrink('obs_rush_1d', 'rush_1d_rate',      'n_carries',  'k_rush_1d') }} as proj_rush_1d_rate,
        {{ reliability_shrink('obs_catch',   'catch_rate',        'n_targets',  'k_catch') }}   as proj_catch_rate,
        {{ reliability_shrink('obs_ypt',     'yards_per_target',  'n_targets',  'k_ypt') }}     as proj_yards_per_target,
        {{ reliability_shrink('obs_rec_td',  'rec_td_rate',       'n_targets',  'k_rec_td') }}  as proj_rec_td_rate,
        {{ reliability_shrink('obs_rec_1d',  'rec_1d_rate',       'n_targets',  'k_rec_1d') }}  as proj_rec_1d_rate,

        -- minor components: no fitted k -> league-rate x volume (no per-player signal)
        pass_2pt_rate, rush_2pt_rate, rush_fumble_rate, rec_2pt_rate, rec_fumble_rate
    from derived

)

-- final: assemble each projected season component = projected volume x projected rate
select
    projection_season,
    player_id,
    position,
    team,
    seasons_of_history,
    is_projection_low_confidence,
    round(projected_games, 1)                                   as projected_games,

    -- projected opportunity volume
    round(proj_pass_attempts, 1)                                as proj_pass_attempts,
    round(proj_dropbacks, 1)                                    as proj_dropbacks,
    round(proj_carries, 1)                                      as proj_carries,
    round(proj_targets, 1)                                      as proj_targets,

    -- ===== PASSING components =====
    round(proj_pass_attempts * proj_completion_pct, 1)          as passing_completions,
    round(proj_pass_attempts * proj_yards_per_attempt, 1)       as passing_yards,
    round(proj_pass_attempts * proj_pass_td_rate, 2)            as passing_tds,
    round(proj_pass_attempts * proj_int_rate, 2)                as passing_interceptions,
    round(proj_dropbacks * proj_sack_rate, 1)                   as sacks_suffered,
    round(proj_pass_attempts * pass_2pt_rate, 2)                as passing_2pt_conversions,

    -- ===== RUSHING components =====
    round(proj_carries * proj_yards_per_carry, 1)               as rushing_yards,
    round(proj_carries * proj_rush_td_rate, 2)                  as rushing_tds,
    round(proj_carries * proj_rush_1d_rate, 1)                  as rushing_first_downs,
    round(proj_carries * rush_2pt_rate, 2)                      as rushing_2pt_conversions,
    round(proj_carries * rush_fumble_rate, 2)                   as rushing_fumbles_lost,

    -- ===== RECEIVING components =====
    round(proj_targets * proj_catch_rate, 1)                    as receptions,
    round(proj_targets * proj_yards_per_target, 1)              as receiving_yards,
    round(proj_targets * proj_rec_td_rate, 2)                   as receiving_tds,
    round(proj_targets * proj_rec_1d_rate, 1)                   as receiving_first_downs,
    round(proj_targets * rec_2pt_rate, 2)                       as receiving_2pt_conversions,
    round(proj_targets * rec_fumble_rate, 2)                    as receiving_fumbles_lost
from assembled
