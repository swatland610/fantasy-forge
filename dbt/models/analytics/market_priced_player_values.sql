-- market_priced_player_values
-- Grain: one row per player_id -- Cool Place-specific, LIVE SEASON ONLY (matching
-- player_auction_prices' and preferred_analyst_lean's discipline). Covers every player for whom
-- the VORP engine's own-history projection is NOT trustworthy, for either of two distinct
-- reasons (`reason` column):
--
--   'rookie'            -- entirely absent from player_values. The VORP engine requires 1-3
--                          seasons of NFL history (proj_player_season_components' window join),
--                          so true rookies are absent BY CONSTRUCTION (documented V3 scope cut)
--                          -- there is nothing to shrink toward or fit a per-game rate from.
--
--   'situation_change'  -- PRESENT in player_values, but their most-recent-history team
--                          (player_values.team, from proj_player_season_components' trailing
--                          window) no longer matches their current roster team
--                          (dim_players.team). Their carries/targets-per-game opportunity is a
--                          pure recency-weighted average of usage in a SITUATION THEY'VE LEFT --
--                          a new team, coaching staff, or depth chart the model has zero signal
--                          about ("no role-change/depth-chart blending" is the same documented
--                          V3 scope cut as the rookie gap). TESTED 2026-09-06
--                          (scripts/fit_team_change_blend.py): rescaling a player's own trailing
--                          per-game opportunity by the new team's positional volume relative to
--                          league average does NOT improve prediction of actual next-season
--                          usage for historical team-changers (RB/WR/TE/QB all flat-to-worse on
--                          both MAE and correlation) -- a team-level volume signal is too crude
--                          a proxy for an individual role. Rather than keep an own-history number
--                          the model cannot correct, or fabricate a role-share estimate with no
--                          fitted basis, these players are repriced from the SAME market-consensus
--                          signal as rookies: real analysts already have the actual depth-chart/
--                          role information this pipeline doesn't ingest.
--
-- Both groups share one pricing path because they share the same root cause: this pipeline has
-- no reliable OWN-HISTORY signal for them. Real market signals (CBS $ and your preferred
-- analysts) don't depend on NFL season history at all -- they reflect an analyst's current
-- knowledge of the player's real 2026 situation.
--
-- SCOPE: rookies (draft_year = the live season) absent from player_values, PLUS situation-change
-- veterans present in player_values with a team mismatch -- in both cases only where at least one
-- real signal exists (CBS $ or an analyst ranking). Most of a draft class / most uncontested
-- team-changers are correctly excluded when there's no signal to price from.
--
-- PRICING: CBS $ is the primary signal where it exists (same budget/scarcity scaling as the
-- veteran CBS proxy in player_auction_prices.sql's header): CBS_BUDGET_SCALE assumes their sheet
-- uses a $100 budget (inferred, not confirmed); QB_SCARCITY_RATIO rescales CBS's own implied QB
-- budget share to our real superflex share. Floored at $1 like the veteran model (Sleeper's
-- minimum bid), so a $0 CBS floor value still shows as a real, biddable price.
--
-- estimated_price is NULL (not fabricated) for a player with analyst coverage but no CBS $ at
-- all. avg_analyst_position_rank is NULL for a player with CBS $ but no analyst coverage. Both
-- can be non-null.
--
-- NOT folded into player_auction_prices' $3,000 budget-conservation invariant (a deliberate
-- scope choice): these players are priced independently rather than reducing other prices to
-- make room. Total implied league spend therefore exceeds $3,000 in principle -- acceptable
-- slack given veteran prices already have headroom (many are floored at $1) and the market-priced
-- pool is small relative to the whole board.

with live_season as (

    select max(projection_season) as projection_season
    from {{ ref('player_values') }}

),

rookies as (

    select player_id, position, 'rookie' as reason
    from {{ ref('dim_players') }}
    where draft_year = (select projection_season from live_season)
      and position in ('QB', 'RB', 'WR', 'TE')
      and not exists (
        select 1
        from {{ ref('player_values') }} pv
        where pv.player_id = dim_players.player_id
          and pv.league_id = 'coolplace'
          and pv.projection_season = (select projection_season from live_season)
      )

),

situation_changed as (

    -- veteran with an existing player_values row, but the trailing-history team
    -- (pv.team, from proj_player_season_components) no longer matches their current roster
    -- team (dp.team) -- their own-history opportunity projection reflects a situation they've
    -- left. dp.team is NOT NULL required so a retired/inactive player with a stale roster team
    -- isn't misflagged as a "change" simply because dim_players' team field is empty.
    select pv.player_id, pv.position, 'situation_change' as reason
    from {{ ref('player_values') }} pv
    join {{ ref('dim_players') }} dp on dp.player_id = pv.player_id
    where pv.league_id = 'coolplace'
      and pv.projection_season = (select projection_season from live_season)
      and dp.team is not null
      and pv.team is not null
      and pv.team != dp.team

),

no_history_players as (

    select * from rookies
    union all
    select * from situation_changed

),

analyst_consensus as (

    select
        player_id,
        avg(normalized_position_rank) as avg_analyst_position_rank,
        count(distinct analyst)       as n_analysts
    from {{ ref('stg_analysts__draft_rankings') }}
    where has_gsis_match
    group by player_id

),

priced as (

    select
        n.player_id,
        n.position,
        n.reason,
        cbs.auction_value_dollar as cbs_price_raw,
        ac.avg_analyst_position_rank,
        ac.n_analysts,
        case
            when cbs.auction_value_dollar is null then null
            else greatest(
                1,
                round(
                    cbs.auction_value_dollar
                    * 2.5  -- CBS_BUDGET_SCALE: $250 / their inferred $100 budget
                    * case when n.position = 'QB' then (0.234 / (78.0 / 1194)) else 1 end
                )::integer
            )
        end as estimated_price
    from no_history_players as n
    left join {{ ref('stg_analysts__auction_values') }} as cbs on cbs.player_id = n.player_id
    left join analyst_consensus as ac on ac.player_id = n.player_id
    where cbs.player_id is not null or ac.player_id is not null

)

select * from priced
