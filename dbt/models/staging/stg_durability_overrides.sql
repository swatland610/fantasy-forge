-- stg_durability_overrides
-- Grain: one row per player_name in durability_overrides_2026 -- a small, human-curated,
-- fully auditable list of manual projected_games overrides.
--
-- WHY THIS EXISTS: the reliability-shrunk projected_games (proj_player_season_components.sql)
-- corrects HOW MUCH we trust a player's own trailing games record given their amount of
-- history -- it cannot correct for WHAT that record contains. A player whose short recent
-- seasons came from two distinct, unrelated, non-chronic injuries (confirmed via
-- stg_nflverse__injuries where possible) looks statistically identical to a genuinely fragile
-- player under a games_played-only model. Building a real injury-chronicity classifier is out
-- of scope (same category as the documented "no aging curve" V3 scope cut, and
-- stg_nflverse__injuries doesn't even cover the current season yet) -- this is the deliberately
-- manual, transparent stopgap instead: every override carries a written reason in the seed,
-- not a silent pipeline hack.
--
-- override_games is a JUDGMENT CALL, not a fitted number -- treat it as such; adjust the seed
-- directly if your own read differs.

with source as (

    select *
    from {{ ref('durability_overrides_2026') }}

),

players as (

    select display_name, player_id, position
    from {{ ref('stg_nflverse__players') }}

),

matched as (

    select
        s.player_name,
        s.position,
        s.override_games,
        s.reason,
        s.added_date,
        p.player_id
    from source as s
    left join players as p
        on {{ normalize_player_name('s.player_name') }} = {{ normalize_player_name('p.display_name') }}
        and s.position = p.position

)

select
    player_name,
    player_id,
    (player_id is not null) as has_gsis_match,
    position,
    override_games,
    reason,
    added_date
from matched
