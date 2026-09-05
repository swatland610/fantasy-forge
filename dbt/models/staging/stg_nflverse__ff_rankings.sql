-- stg_nflverse__ff_rankings
-- Grain: one row per (projection_season, fantasypros_id).
-- The market baseline for the V-GATE backtest: FantasyPros redraft-superflex expert consensus
-- rankings (ECR), one CONTEMPORANEOUS PRESEASON snapshot per season. This is the "beat the
-- market" yardstick -- the projection has to out-rank this to justify building anything on top.
--
-- SCOPE / FILTERS (each is a deliberate, surfaced choice):
--   * ecr_type = 'rsf' -> redraft superflex, the format that matches the boc league's lineup
--     (1QB + 1 SUPERFLEX). Dynasty (dsf) and 1QB (rp/ro) markets are out of scope for the
--     single-season redraft gate.
--   * LATEST AUGUST snapshot per year -> a true preseason read with NO look-ahead: late-August
--     scrapes (2021-08-27 ... 2025-08-29) land just before Week 1, so they encode preseason
--     consensus only, never in-season results. September scrapes are excluded precisely because
--     they can contain Week 1 outcomes.
--   * projection_season = the scrape's calendar year (an Aug-YYYY snapshot ranks the YYYY season),
--     so it joins straight to proj_player_fantasy_points / player_values on projection_season.
--
-- CROSSWALK (NULLs surfaced, not coalesced or dropped): FantasyPros `id` is joined to gsis via
--   stg_nflverse__ff_playerids.fantasypros_id. ~7% of rsf players don't resolve to a gsis id
--   (obscure/duplicate FantasyPros entries); those rows are KEPT with player_id = NULL and
--   has_gsis_match = false so the harness can report coverage and decide, rather than silently
--   shrinking the market pool. ecr (consensus rank, lower = better) is the field the backtest
--   ranks on.

with source as (

    select
        id        as fantasypros_id,
        player    as player_name,
        pos       as position,
        team,
        ecr,
        sd        as ecr_sd,
        best      as ecr_best,
        worst     as ecr_worst,
        cast(scrape_date as date) as scrape_date
    from {{ source('nflverse', 'ff_rankings') }}
    where ecr_type = 'rsf'

),

preseason as (

    -- keep only August snapshots, then the LATEST August snapshot in each season
    select *
    from source
    where month(scrape_date) = 8
    qualify scrape_date = max(scrape_date) over (partition by year(scrape_date))

),

crosswalk as (

    select fantasypros_id, player_id
    from {{ ref('stg_nflverse__ff_playerids') }}
    where fantasypros_id is not null

)

select
    year(p.scrape_date)                         as projection_season,
    p.scrape_date,
    p.fantasypros_id,
    x.player_id,                                 -- gsis id; NULL when unmatched (surfaced)
    (x.player_id is not null)                    as has_gsis_match,
    p.player_name,
    p.position,
    p.team,
    p.ecr,                                       -- expert consensus rank (lower = better)
    p.ecr_sd,
    p.ecr_best,
    p.ecr_worst
from preseason as p
left join crosswalk as x
    on cast(p.fantasypros_id as varchar) = cast(x.fantasypros_id as varchar)
