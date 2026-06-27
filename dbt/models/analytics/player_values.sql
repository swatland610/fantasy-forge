-- player_values
-- Grain: one row per (projection_season, league_id, player_id).
-- Phase V5 deliverable: the cross-position value board. VORP = a player's projected points
-- (in their league's scoring format) minus that league's positional replacement level, so a
-- QB and a WR become directly comparable on a single value scale. Fans out across every league
-- in the leagues seed AND every projection season in one idempotent build.
--
-- SEASON-GENERALIZED: the live 2026 board is just projection_season = 2026; backtest folds are
-- projection_season = 2021..2025, consumed by the V-GATE harness and compared against
-- contemporaneous superflex ECR. overall_rank / position_rank are computed WITHIN each
-- (projection_season, league_id), so each fold's board ranks only against itself.
--
-- The superflex QB premium is NOT asserted here -- it falls out of replacement_levels: a deeper
-- SF QB demand cliff raises the QB replacement rank, which (counterintuitively) tends to LOWER
-- the QB replacement points relative to a 1QB league and lifts elite QB VORP. The V-GATE smell
-- test (elite QBs near the top of the board) is what confirms it worked.
--
-- is_projection_low_confidence is carried through, not filtered: thin/stale-history players are
-- still valued, just flagged, so the consumer can discount them rather than have them vanish.

with pts as (

    select
        projection_season,
        player_id,
        position,
        team,
        format_name,
        fantasy_points,
        is_projection_low_confidence
    from {{ ref('proj_player_fantasy_points') }}

),

valued as (

    -- join each league to the points in its format and to its positional replacement level
    -- (matched on the same projection season, so folds never cross-contaminate)
    select
        p.projection_season,
        l.league_id,
        p.player_id,
        p.position,
        p.team,
        l.scoring_format,
        p.fantasy_points                          as projected_points,
        rl.replacement_points,
        p.fantasy_points - rl.replacement_points  as vorp,
        p.is_projection_low_confidence
    from {{ ref('leagues') }} as l
    join pts as p
        on p.format_name = l.scoring_format
    join {{ ref('replacement_levels') }} as rl
        on  rl.projection_season = p.projection_season
        and rl.league_id         = l.league_id
        and rl.position          = p.position

)

select
    projection_season,
    league_id,
    player_id,
    position,
    team,
    scoring_format,
    round(projected_points, 1)   as projected_points,
    round(replacement_points, 1) as replacement_points,
    round(vorp, 1)               as vorp,
    is_projection_low_confidence,
    -- player_id is a deterministic tiebreaker so ranks are reproducible across runs
    -- (equal-VORP players would otherwise order by arbitrary scan order)
    row_number() over (partition by projection_season, league_id            order by vorp desc, player_id) as overall_rank,
    row_number() over (partition by projection_season, league_id, position  order by vorp desc, player_id) as position_rank
from valued
