-- replacement_levels
-- Grain: one row per (projection_season, league_id, position).
-- Phase V5: the demand-aware replacement level -- the projected points of the LAST STARTABLE
-- player at each position in each league, computed per projection season. This is the baseline
-- VORP subtracts, and it is the single piece of machinery that makes the superflex QB premium
-- emerge instead of being asserted.
--
-- SEASON-GENERALIZED: ranks are computed within (projection_season, format, position), so each
-- backtest fold (2021-2025) gets its own replacement levels from its own projected pool, and the
-- live 2026 board is just projection_season = 2026. The demand model is league config (no season
-- dependence); the projection_season comes from the ranked projection pool.
--
-- DEMAND MODEL (config-as-data, from the leagues + roster_slots seeds):
--   startable_demand[league, pos]
--     = num_teams * ( dedicated_starters
--                   + flex_slots      * flex_weight[pos]        -- regular FLEX pool (R/W/T)
--                   + superflex_slots * superflex_weight[pos] )  -- SUPERFLEX pool (Q/R/W/T)
--   A superflex slot pushes ~0.85 of a QB into demand per team, so a 10-team SF league demands
--   ~18-19 startable QBs -- nearly 2x a 1QB league. That deeper QB demand cliff is exactly what
--   lifts elite QBs up the cross-position board below.
--
-- COVERAGE: a missing (league, position) row here deletes that position from player_values
--   entirely (it inner-joins this model). Two guards: the rank is CLAMPED to the pool size so a
--   shallow pool still yields a row, and a not_null test on replacement_rank_used plus the
--   roster_slots relationship test catch a missing seed row loudly instead of silently.
--
-- REPLACEMENT RANK: fractional demand is rounded to the nearest integer within-position rank
--   (v1, deliberately simple). Linear interpolation between the floor/ceil ranks is a possible
--   v2 refinement; at the replacement cliff the gap between adjacent ranks is a few points, so
--   rounding is adequate for a ranking product.
--
-- POOL CAVEAT (surfaced, not hidden): the ranked pool is proj_player_fantasy_points, which by
--   construction contains only RETURNING players with history -- rookies are absent (a v2 item).
--   So the startable pool is missing the ~rookie-occupied roster spots, which makes the
--   replacement player marginally weaker than reality and inflates VORP by a near-constant per
--   position. Acceptable for a relative board; revisit when the rookie sub-model lands.
--   is_projection_low_confidence players ARE kept in the pool -- they occupy real roster spots.

with demand as (

    -- fractional startable demand per (league, position) from the seeds (season-independent)
    select
        l.league_id,
        rs.position,
        l.scoring_format,
        l.num_teams * (
            rs.dedicated_starters
          + l.flex_slots      * rs.flex_weight
          + l.superflex_slots * rs.superflex_weight
        ) as startable_demand
    from {{ ref('leagues') }} as l
    join {{ ref('roster_slots') }} as rs using (league_id)

),

ranked as (

    -- rank projected players within each (projection_season, format, position); best = rank 1
    select
        projection_season,
        format_name,
        position,
        player_id,
        fantasy_points,
        row_number() over (
            partition by projection_season, format_name, position
            -- player_id is a deterministic tiebreaker: points are rounded to 0.1 so ties at the
            -- replacement rank are common, and without it replacement_player_id (and therefore
            -- every VORP in that league-position) could change across rebuilds with no input
            -- change. player_values does the same for the same reason.
            order by fantasy_points desc, player_id
        ) as pos_rank,
        count(*) over (
            partition by projection_season, format_name, position
        ) as pos_pool_size
    from {{ ref('proj_player_fantasy_points') }}

)

select
    ranked.projection_season,
    d.league_id,
    d.position,
    d.scoring_format,
    round(d.startable_demand, 2)                  as startable_demand,
    cast(round(d.startable_demand) as integer)    as replacement_rank,
    ranked.pos_rank                               as replacement_rank_used,
    ranked.player_id                              as replacement_player_id,
    ranked.fantasy_points                         as replacement_points
from demand as d
join ranked
    on  ranked.format_name = d.scoring_format
    and ranked.position    = d.position
    -- CLAMP to the deepest projected player at this position. Matching the demand rank exactly
    -- produced NO ROW whenever the projected pool was shallower than demand, and player_values
    -- inner-joins this model -- so an entire position silently vanished from the board while
    -- unique_combination_of_columns and every not_null test still passed. Clamping keeps the row
    -- and replacement_rank_used exposes when the clamp bit (used < replacement_rank), so a too-
    -- shallow pool is visible rather than invisible.
    and ranked.pos_rank    = least(
            cast(round(d.startable_demand) as integer),
            ranked.pos_pool_size
        )
