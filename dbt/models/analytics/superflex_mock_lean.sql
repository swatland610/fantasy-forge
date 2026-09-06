-- superflex_mock_lean
-- Grain: one row per (league_id, player_id) -- ALL positions (QB/RB/WR/TE), LIVE SEASON ONLY.
-- Generalized 2026-09-06 from the original QB-only superflex_mock_qb_lean, after the source
-- mock draft was fully re-transcribed for every position (see
-- stg_superflex_mock__draft_capital's header for the two-pass verification).
--
-- WHY THIS EXISTS, SEPARATE FROM preferred_analyst_lean: for QB specifically, your three
-- preferred analysts only publish standard-league rankings, which can't be rescaled into a
-- superflex-specific order (an ordinal ranking isn't a proportion the way a dollar share is --
-- see player_auction_prices.sql). For RB/WR/TE, superflex format doesn't shift demand the same
-- way (a RB's value doesn't change because the league starts 2 QBs instead of 1), so
-- preferred_analyst_lean was already a reasonable signal there -- this model isn't a
-- replacement for it, just an additional real, independent cross-check: genuine
-- revealed-preference demand from 12 real drafters in one real superflex-format draft, not a
-- stated ranking.
--
-- CAVEATS (same as stg_superflex_mock__draft_capital -- read before trusting this over the
-- model): n=1 mock, not a market consensus. Not every pick in the draft is present (a handful
-- of unidentifiable late-round names were excluded rather than guessed). mock_position_rank is
-- computed only over the players THIS mock actually drafted at that position -- a low mock
-- pick count for a position (e.g. only a few TEs went in the mock's early rounds) does not mean
-- the mock's drafters ignored that position, just that this one draft didn't need many of them
-- that early.
--
-- mock_position_rank: players ranked by mock pick_no ascending, WITHIN position (pick order
-- restarts at 1 for each position). lean = model's position_rank minus mock_position_rank.
-- POSITIVE lean = the mock's drafters valued this player HIGHER than our model does (mock's
-- rank number is smaller/earlier); NEGATIVE = our model likes the player more than the mock's
-- room did.

with live_season as (

    select max(projection_season) as projection_season
    from {{ ref('player_values') }}

),

mock_ranked as (

    select
        player_id,
        position,
        pick_no,
        extraction_flagged,
        row_number() over (partition by position order by pick_no asc) as mock_position_rank
    from {{ ref('stg_superflex_mock__draft_capital') }}
    where has_gsis_match

),

board as (

    select league_id, player_id, position, vorp, position_rank as model_position_rank
    from {{ ref('player_values') }}
    where projection_season = (select projection_season from live_season)

)

select
    b.league_id,
    b.player_id,
    b.position,
    b.vorp,
    b.model_position_rank,
    m.pick_no as mock_pick_no,
    m.mock_position_rank,
    m.extraction_flagged as mock_extraction_flagged,
    b.model_position_rank - m.mock_position_rank as lean
from board as b
join mock_ranked as m
    on b.player_id = m.player_id
    and b.position = m.position
