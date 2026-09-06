-- superflex_mock_qb_lean
-- Grain: one row per (league_id, player_id) -- QB ONLY, LIVE SEASON ONLY. Same shape and
-- intent as preferred_analyst_lean, but sourced from stg_superflex_mock__qb_capital instead
-- of Cummings/Eisenberg/Gibbs.
--
-- WHY THIS EXISTS, SEPARATE FROM preferred_analyst_lean: your three preferred analysts rank
-- QBs for a standard 1-QB league -- see player_auction_prices.sql's header on why that can't
-- be rescaled into a superflex-specific ORDER (a dollar SHARE rescales with math; an ordinal
-- ranking doesn't, since it reflects an analyst's own standard-league mental model, not a
-- proportion). This model instead treats the real 12-team superflex mock draft's QB pick order
-- as its own independent "superflex ECR" -- genuine revealed-preference demand from 12
-- drafters valuing QBs against a real SUPER_FLEX slot, not a single analyst's stated opinion
-- rescaled to fit. We are NOT claiming this speaks for Cummings/Eisenberg/Gibbs; it's a
-- distinct source, kept in its own model rather than blended into preferred_analyst_lean.
--
-- CAVEATS (same as stg_superflex_mock__qb_capital -- read before trusting this over the
-- model): n=1 mock, not a market consensus. Several picks carry flagged extraction
-- uncertainty (extraction_flagged) -- treat those pick numbers as directional, not exact.
-- QB-only: the mock has no non-QB signal worth pulling (RB/WR/TE aren't demand-shifted by
-- superflex the way QB is, so preferred_analyst_lean is already adequate there).
--
-- WHY LIVE SEASON ONLY: same discipline as preferred_analyst_lean -- the mock is a single
-- 2026-draft snapshot, not a season-keyed history, so this cannot extend to the backtest
-- folds without silently applying 2026 draft-capital opinions to a 2022 VORP board.
--
-- mock_position_rank: QBs ranked by mock pick_no ascending (pick 1 = QB1). lean = model's
-- position_rank minus mock_position_rank. POSITIVE lean = the mock's drafters valued this QB
-- HIGHER than our model does (mock's rank number is smaller/earlier); NEGATIVE = our model
-- likes the player more than the mock's room did. Same sign convention as
-- preferred_analyst_lean for consistency.

with live_season as (

    select max(projection_season) as projection_season
    from {{ ref('player_values') }}

),

mock_ranked as (

    select
        player_id,
        pick_no,
        extraction_flagged,
        row_number() over (order by pick_no asc) as mock_position_rank
    from {{ ref('stg_superflex_mock__qb_capital') }}
    where has_gsis_match

),

board as (

    select league_id, player_id, vorp, position_rank as model_position_rank
    from {{ ref('player_values') }}
    where projection_season = (select projection_season from live_season)
      and position = 'QB'

)

select
    b.league_id,
    b.player_id,
    b.vorp,
    b.model_position_rank,
    m.pick_no as mock_pick_no,
    m.mock_position_rank,
    m.extraction_flagged as mock_extraction_flagged,
    b.model_position_rank - m.mock_position_rank as lean
from board as b
join mock_ranked as m
    on b.player_id = m.player_id
