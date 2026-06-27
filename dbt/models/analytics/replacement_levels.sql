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
            order by fantasy_points desc
        ) as pos_rank
    from {{ ref('proj_player_fantasy_points') }}

)

select
    ranked.projection_season,
    d.league_id,
    d.position,
    d.scoring_format,
    round(d.startable_demand, 2)                  as startable_demand,
    cast(round(d.startable_demand) as integer)    as replacement_rank,
    ranked.player_id                              as replacement_player_id,
    ranked.fantasy_points                         as replacement_points
from demand as d
join ranked
    on  ranked.format_name = d.scoring_format
    and ranked.position    = d.position
    and ranked.pos_rank    = cast(round(d.startable_demand) as integer)
