-- stg_superflex_mock__draft_capital
-- Grain: one row per player_name in superflex_mock_draft_capital_2026 -- one real 12-team
-- superflex mock draft's FULL pick order (12 different drafters), all four fantasy skill
-- positions (QB/RB/WR/TE). K/DST picks are out of scope (not priced anywhere in this
-- pipeline) and excluded from the seed entirely.
--
-- HISTORY: originally QB-only (stg_superflex_mock__qb_capital), built to fix the superflex
-- QB-scarcity gap CBS's auction sheet and standard-league analysts can't cover. Generalized
-- to all positions 2026-09-06 on request, after two independent full-draft extraction passes
-- (compared pick-by-pick; the whole 204-pick draft agreed except one drafter attribution,
-- resolved via a third targeted fetch) gave high confidence in a complete re-transcription.
--
-- CROSSWALK: normalized name + position (unlike the original QB-only seed, position IS
-- required here -- e.g. pick 49's "Javonte Williams RB DAL" and pick 76's "Jameson Williams
-- WR DET" share a last name and would otherwise collide). Team is NOT used as a join key or
-- even a reliable tiebreaker here: CBS's own draft-result table has real, frequent stale team
-- labels (players shown at a pre-trade team -- e.g. Stefon Diggs listed WAS instead of NE,
-- DK Metcalf... wait, Metcalf's listed team was actually correct; see the seed's per-row notes
-- for the ~15 rows where this was caught). Every such case is noted in the seed with the real
-- team, not silently trusted or corrected here -- this model crosswalks on name+position alone.
--
-- COVERAGE: NOT every one of the 204 picks -- a handful of very late-round depth picks (~10-15)
-- were excluded from the seed entirely rather than guessed at from an ambiguous abbreviated
-- name ("T. Tucker", "K. Mitchell", etc.) with no team/context strong enough to identify with
-- confidence. Missing is better than wrong for a crosswalk key.

with source as (

    select *
    from {{ ref('superflex_mock_draft_capital_2026') }}

),

players as (

    select display_name, player_id, position, last_season
    from {{ ref('stg_nflverse__players') }}

),

matched as (

    select
        s.player_name,
        s.position,
        s.pick_no,
        s.drafter,
        s.notes,
        s.source_url,
        s.pulled_date,
        p.player_id
    from source as s
    left join players as p
        on {{ normalize_player_name('s.player_name') }} = {{ normalize_player_name('p.display_name') }}
        and s.position = p.position
    -- normalize_player_name strips ONE trailing suffix (Jr./Sr./II/III/IV), so a name like
    -- "Marvin Harrison Jr." collides with an unrelated same-named player who has no suffix to
    -- strip (here, the retired WR Marvin Harrison, last active 2008) -- the exact collision
    -- already documented in stg_analysts__draft_rankings.sql's header. That model breaks ties
    -- on TEAM; this one can't -- the mock's own source table has real, frequent stale team
    -- labels (see this model's header), so team isn't trustworthy as a tiebreaker here.
    -- last_season is: a rookie/current player picked in a REAL 2026 mock draft is essentially
    -- never the more-retired candidate in a same-name collision.
    qualify row_number() over (
        partition by s.player_name, s.position, s.pick_no
        order by p.last_season desc nulls last
    ) = 1

)

select
    player_name,
    player_id,
    (player_id is not null) as has_gsis_match,
    position,
    pick_no,
    drafter,
    (notes is not null and notes != '') as extraction_flagged,
    notes,
    source_url,
    pulled_date
from matched
