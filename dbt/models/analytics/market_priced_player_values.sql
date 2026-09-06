-- rookie_player_values
-- Grain: one row per player_id -- Cool Place-specific, LIVE SEASON ONLY (matching
-- player_auction_prices' and preferred_analyst_lean's discipline). Covers players entirely
-- absent from player_values: the VORP engine requires 1-3 seasons of NFL history
-- (proj_player_season_components' window join), so true rookies are absent there BY
-- CONSTRUCTION, not a bug (documented V3 scope cut) -- there is nothing to shrink toward or
-- fit a per-game rate from. This model is the deliberately separate, lower-rigor stand-in:
-- real market signals (CBS $ and your preferred analysts) that don't depend on NFL season
-- history at all.
--
-- SCOPE: only rookies (draft_year = the live season) who are ALSO absent from player_values
-- and have at least one real signal (CBS $ or an analyst ranking) -- most of a draft class is
-- undrafted-in-any-fantasy-format depth and correctly excluded (no signal to price from).
--
-- PRICING: CBS $ is the primary signal where it exists (raw values here mostly $0-13,
-- reflecting how thin real rookie fantasy value is in year one) -- same budget/scarcity
-- scaling as the veteran CBS proxy (see player_auction_prices.sql's header for the QB
-- superflex-share derivation): CBS_BUDGET_SCALE assumes their sheet uses a $100 budget
-- (inferred, not confirmed -- see that model); QB_SCARCITY_RATIO rescales CBS's own implied
-- QB budget share to our real superflex share. Floored at $1 like the veteran model (Sleeper's
-- minimum bid), so a $0 CBS floor value still shows as a real, biddable price.
--
-- estimated_price is NULL (not fabricated) for a player with analyst coverage but no CBS $ at
-- all (as of this build: Fernando Mendoza, Kenyon Sadiq, Kaytron Allen) -- there is no dollar
-- signal to scale for them, only a rank. avg_analyst_position_rank is NULL for a player with
-- CBS $ but no analyst coverage. Both can be non-null.
--
-- NOT folded into player_auction_prices' $3,000 budget-conservation invariant (a deliberate
-- scope choice): rookies are priced independently rather than reducing veteran prices to make
-- room. Total implied league spend across veterans + rookies therefore exceeds $3,000 in
-- principle -- acceptable slack given veteran prices already have headroom (many are floored
-- at $1 well below a pure proportional split) and real rookie $ are small.

with live_season as (

    select max(projection_season) as projection_season
    from {{ ref('player_values') }}

),

rookies as (

    select player_id, position
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
        r.player_id,
        r.position,
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
                    * case when r.position = 'QB' then (0.234 / (78.0 / 1194)) else 1 end
                )::integer
            )
        end as estimated_price
    from rookies as r
    left join {{ ref('stg_analysts__auction_values') }} as cbs on cbs.player_id = r.player_id
    left join analyst_consensus as ac on ac.player_id = r.player_id
    where cbs.player_id is not null or ac.player_id is not null

)

select * from priced
