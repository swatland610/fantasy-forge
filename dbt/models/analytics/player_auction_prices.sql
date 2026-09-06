-- player_auction_prices
-- Grain: one row per (player_id) within the Cool Place startable pool -- QB 32 / RB 49 /
-- WR 54 / TE 16, unchanged from the original manual methodology in method-and-caveats.md.
-- Below these caps, VORP stops measuring scarcity and starts measuring how gently a
-- position's curve flattens.
--
-- In practice the priced pool is smaller than 151 -- the vorp > 0 filter below drops
-- players who are below replacement level even within the cap (currently ~90 players
-- get a real price; the rest are implied $1 fills, same convention CBS's own sheet uses).
--
-- This is Cool Place-specific (hardcoded $250 x 12-team budget, superflex QB treatment),
-- unlike player_values which is parameterised per league. There is no equivalent auction
-- format for boc (dynasty, no auction), so there is nothing to generalise to yet.
--
-- Two-part concentration model, not one unified gamma across all positions:
--
--   QB: gamma = 0.78, budget share held at 23.4% (2026-01-03 cool-place.md superflex demand
--       math: 12 x (1 dedicated + 0.85 superflex) = 22.2 startable QBs). CBS's auction sheet
--       assumes a standard 1-QB league and carries no superflex signal, so QB pricing still
--       can't be calibrated to real money -- this remains the original hand-anchored number
--       (solved so the #1 overall player lands near $80), not fit to anything.
--
--   RB/WR/TE: gamma = 0.595, fit by log-log OLS against real CBS Consensus auction $
--       (stg_analysts__auction_values) -- see scripts/fit_auction_gamma.py. Fit pooled across
--       all three positions rather than per-position: RB alone fits reasonably (n=24,
--       r2=0.66), WR is weak on its own (n=30, r2=0.25), and TE is unreliable alone (n=10,
--       r2=0.08) -- pooling avoids overfitting those small per-position samples. Pooled fit:
--       n=64, r2=0.33 -- moderate, not strong. This is real market data, but treat the
--       resulting $ as a calibrated estimate, not a verified one. Re-run
--       scripts/fit_auction_gamma.py and update the constant below if the CBS seed refreshes
--       with a materially different sheet.
--
-- Budget conservation: sum(auction_price) across both pools = $3,000 (the league's
-- $250/team x 12 teams), same total the original single-gamma model conserved.

with ranked as (

    select
        player_id,
        position,
        vorp
    from {{ ref('player_values') }}
    where league_id = 'coolplace'
      and projection_season = 2026
      and player_status = 'ACT'
      and vorp > 0
    qualify row_number() over (partition by position order by vorp desc) <=
        case position
            when 'QB' then 32
            when 'RB' then 49
            when 'WR' then 54
            when 'TE' then 16
            else 0
        end

),

qb_pool as (

    select player_id, position, vorp
    from ranked
    where position = 'QB'

),

nonqb_pool as (

    select player_id, position, vorp
    from ranked
    where position in ('RB', 'WR', 'TE')

),

qb_priced as (

    select
        player_id,
        position,
        vorp,
        3000 * 0.234
            * power(vorp, 0.78) / sum(power(vorp, 0.78)) over ()
            as auction_price_raw
    from qb_pool

),

nonqb_priced as (

    select
        player_id,
        position,
        vorp,
        3000 * (1 - 0.234)
            * power(vorp, 0.595) / sum(power(vorp, 0.595)) over ()
            as auction_price_raw
    from nonqb_pool

),

combined as (

    select * from qb_priced
    union all
    select * from nonqb_priced

)

select
    player_id,
    position,
    vorp,
    greatest(1, round(auction_price_raw)::integer) as auction_price
from combined
