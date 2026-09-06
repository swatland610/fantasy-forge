-- stg_superflex_mock__qb_capital
-- Grain: one row per player_name in superflex_mock_qb_capital_2026 (a single real 12-team
-- superflex mock draft -- CBS's "Analysts show patience..." Nov 2026 mock, 12 different
-- drafters, not one analyst's stated opinion).
--
-- WHY THIS EXISTS: CBS's own auction-value sheet is standard 1-QB and has no superflex
-- signal (see player_auction_prices.sql). This mock is real revealed-preference superflex
-- draft capital -- pick_no directly reflects a room of 12 drafters valuing QBs against a
-- SUPER_FLEX slot, which is exactly the comparison our own board needs and CBS's sheet
-- can't give. Use case: sanity-checking whether the projection engine's QB ordering
-- (see proj_player_season_components.sql's documented `projected_games` durability-anchor
-- bias) is producing a plausible relative QB order, independent of our own pipeline.
--
-- CAVEATS -- read before trusting this over the model:
--   * n=1 mock, not a market consensus. One room's behavior, not "the market."
--   * Extraction quality is uneven: the seed's `notes` column flags every name/pick_no this
--     session couldn't cleanly verify (a duplicate C.J. Stroud entry at two picks, one
--     inferred from a re-extraction discrepancy rather than the source article itself,
--     several name variants inferred rather than confirmed). Treat pick_no as directional,
--     not exact, for any row with a note.
--   * Rookie/backup QBs (Tyler Shough, Cameron Ward, Shedeur Sanders) may not resolve to a
--     dim_players row this season -- has_gsis_match surfaces that rather than silently
--     dropping them.

with source as (

    select *
    from {{ ref('superflex_mock_qb_capital_2026') }}

),

players as (

    select display_name, player_id
    from {{ ref('stg_nflverse__players') }}
    where position = 'QB'

),

matched as (

    select
        s.player_name,
        s.pick_no,
        s.drafter,
        s.notes,
        s.source_url,
        s.pulled_date,
        p.player_id
    from source as s
    left join players as p
        on {{ normalize_player_name('s.player_name') }} = {{ normalize_player_name('p.display_name') }}

)

select
    player_name,
    player_id,
    (player_id is not null) as has_gsis_match,
    pick_no,
    drafter,
    (notes is not null and notes != '') as extraction_flagged,
    notes,
    source_url,
    pulled_date
from matched
