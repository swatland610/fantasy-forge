-- proj_player_fantasy_points
-- Grain: one row per (projection_season, player_id, format_name).
-- Phase V4 of the projections roadmap: price the V3 projected season components under every
-- scoring format by pivoting them against the scoring_rules seed -- the same machinery
-- fct_fantasy_points uses for historical actuals, so projected and actual points are scored
-- identically (the backtest depends on that symmetry). Re-runnable for any format with zero
-- model changes: add a row to scoring_rules and it flows through.
--
-- SEASON-GENERALIZED: carries the projection_season key straight through from
-- proj_player_season_components, so this prices every backtest fold (2021-2025) and the live
-- 2026 board in one build. Points depend ONLY on scoring, not roster settings, so leagues
-- sharing a format share these rows. Roster/replacement logic is V5 (player x league x season),
-- built on top of this.
--
-- NULL handling: V3 emits 0 NULL components by construction (every rate falls cleanly to a
-- league baseline -- see proj_player_season_components + reliability_shrink), so UNPIVOT
-- drops nothing and no coalescing is applied. A not_null test on fantasy_points guards this.
--
-- Format notes (inherited from scoring_rules, surfaced here for the reader):
--   * 'ppfd' scores rushing/receiving first downs at +1 and pays 0 for receptions.
--   * 'boc' (the user's superflex dynasty league) = ppfd + a -1/sack QB penalty
--     (sacks_suffered). The pick-6 penalty in that league is a documented data gap
--     (only total interceptions are available), not faked here.
--   * passing_first_downs is never scored (it isn't even projected as a scorable column).

with components as (

    -- projected scorable components only (passing_completions is carried in V3 for
    -- transparency but has no scoring rule, so it's excluded from the melt)
    select
        projection_season,
        player_id,
        position,
        team,
        is_projection_low_confidence,
        passing_yards,
        passing_tds,
        passing_interceptions,
        sacks_suffered,
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
    from {{ ref('proj_player_season_components') }}

),

stats_long as (

    -- melt wide component columns into (stat_name, stat_value) long form
    -- (projection_season, player_id, position, team, is_projection_low_confidence are kept)
    unpivot components
    on
        passing_yards,
        passing_tds,
        passing_interceptions,
        sacks_suffered,
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
        stats_long.projection_season,
        stats_long.player_id,
        stats_long.position,
        stats_long.team,
        stats_long.is_projection_low_confidence,
        scoring_rules.format_name,
        sum(stats_long.stat_value * scoring_rules.points_per) as fantasy_points
    from stats_long
    inner join {{ ref('scoring_rules') }} as scoring_rules
        using (stat_name)
    group by 1, 2, 3, 4, 5, 6

)

select
    projection_season,
    player_id,
    position,
    team,
    format_name,
    is_projection_low_confidence,
    round(fantasy_points, 1) as fantasy_points
from scored
