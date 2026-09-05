-- stg_analysts__draft_rankings
-- Grain: one row per (analyst, player, source_url) from analyst_draft_rankings_2026.
--
-- CROSSWALK (NULLs surfaced, not coalesced or dropped): the seed's `player` is each
-- analyst's own free-text name string, which does NOT match dim_players.display_name
-- exactly -- suffixes (Jr./Sr./II/III/IV), punctuation (A.J. vs AJ), and which side even
-- KEEPS the suffix, all vary by source. Verified against dim_players on initial load:
--   * normalize_player_name() on both sides + position match resolves suffix/punctuation
--     mismatches
--   * team is NOT used as a hard join key, only a tiebreaker -- the analyst's stated team
--     is frequently stale or wrong (offseason movement not yet reflected in the article,
--     transcription slips) even when the player match itself is correct: e.g. one source
--     row has "Bijan Robinson / MIA" (he has never played for Miami) and another has
--     "Daniel Jones / NYG" when he's actually on IND. Requiring team equality would
--     silently drop these otherwise-correct matches. Team codes also differ in spelling
--     (JAC vs JAX, LAR vs LA) -- normalize_team_code() handles that for comparisons; the
--     raw team text is still stored as-is in analyst_stated_team.
--   * exactly 2 (analyst, player, position) rows genuinely match more than one distinct
--     player_id after normalization (a real full-name collision, e.g. rookie "Marvin
--     Harrison Jr." vs a retired "Marvin Harrison", both WR) -- team correctly breaks
--     the tie in both cases, so it's kept as a tiebreaker, not dropped entirely
--   * one true nickname alias remained after normalization (Chigoziem Okonkwo ->
--     dim_players' "Chig Okonkwo") -- that and any future ones like it live in the
--     analyst_name_aliases seed, applied BEFORE normalization below. The alias join keys
--     on (source_name, position) only, NOT team -- team text is exactly as unreliable for
--     an alias row as it is everywhere else in this model, so requiring it to match would
--     silently break future aliases the same way requiring it in the main crosswalk would.
--     was_aliased flags which rows went through this substitution (never coalesce without
--     a flag).
-- Rows that still don't resolve are KEPT with player_id = NULL and has_gsis_match = false
-- so coverage is visible rather than silently dropped.
--
-- CLOSED: is roster_team (dim_players.team) itself trustworthy, or just less wrong than
-- the analyst text? Cross-checked all 60 team_mismatch rows (pre-normalize_team_code) against
-- Sleeper's public player API (independent of nflverse) by gsis_id (13 rows) and by name for
-- the rest (43 rows; mostly 2025/26 rookies Sleeper hasn't yet linked a gsis_id for) -- 56/60
-- confirmed exactly, the remaining 4 confirmed by relaxing suffix punctuation in the name
-- match. Zero real disagreements. So `team` (exposed below, sourced from dim_players/
-- roster_team) is the trustworthy one; analyst_stated_team is kept only for audit/provenance
-- and should NOT be used downstream. Of those original 60, 26 were pure JAC/JAX or LAR/LA
-- spelling (not analyst errors at all) -- team_mismatch below is now computed AFTER
-- normalize_team_code(), so it only fires on genuine disagreement, matching what was
-- actually verified.
--
-- NORMALIZED_POSITION_RANK: a single per-(analyst, position) ordinal, since analysts don't
-- all publish the same kind of rank -- computed here (not by each consumer) so this format
-- quirk is documented and owned in one place:
--   * position_rank, where the source gives one directly (Eisenberg's per-position tier pages)
--   * else derived from overall_rank (Gibbs' single 1-175 board) via row_number within position
--   * else derived from tier alone (Cummings' QB/RB/TE tiers have no numeric rank) via
--     row_number(order by tier) -- this only orders TIERS correctly, not players within a
--     tier; that's the real granularity of a tier-based source and shouldn't be oversold as
--     more precise than it is.

with source as (

    select *
    from {{ ref('analyst_draft_rankings_2026') }}

),

aliased as (

    select
        s.analyst,
        coalesce(a.canonical_display_name, s.player) as player_name,
        (a.canonical_display_name is not null)        as was_aliased,
        s.position,
        s.team,
        s.overall_rank,
        s.position_rank,
        s.tier,
        s.source_url,
        s.pulled_date
    from source as s
    left join {{ ref('analyst_name_aliases') }} as a
        on s.player = a.source_name
        and s.position = a.position

),

players as (

    select display_name, player_id, position, team
    from {{ ref('stg_nflverse__players') }}

),

candidates as (

    select
        a.*,
        p.player_id,
        p.team as roster_team
    from aliased as a
    left join players as p
        on {{ normalize_player_name('a.player_name') }} = {{ normalize_player_name('p.display_name') }}
        and a.position = p.position

),

deduped as (

    -- team is a TIEBREAKER only (see header): prefer a roster-team match when a name+
    -- position pair resolves to more than one player_id, but never require it. Compared
    -- through normalize_team_code() so a JAC/JAX or LAR/LA spelling difference doesn't
    -- defeat a tiebreak that should otherwise succeed.
    select *
    from candidates
    qualify row_number() over (
        partition by analyst, player_name, position, team, source_url
        order by ({{ normalize_team_code('team') }} = {{ normalize_team_code('roster_team') }}) desc, player_id
    ) = 1

)

select
    analyst,
    player_name,
    was_aliased,
    position,
    roster_team as team,                              -- authoritative (dim_players), NOT the source text -- see header
    team as analyst_stated_team,                       -- raw source text, audit/provenance only -- do not use downstream
    player_id,                                        -- gsis id; NULL when unmatched (surfaced)
    (player_id is not null) as has_gsis_match,
    (
        player_id is not null
        and {{ normalize_team_code('team') }} is distinct from {{ normalize_team_code('roster_team') }}
    ) as team_mismatch,
    overall_rank,
    position_rank,
    tier,
    case
        when position_rank is not null then position_rank
        when overall_rank is not null
            then row_number() over (partition by analyst, position order by overall_rank)
        else row_number() over (partition by analyst, position order by tier, player_id)
    end as normalized_position_rank,
    source_url,
    pulled_date
from deduped
