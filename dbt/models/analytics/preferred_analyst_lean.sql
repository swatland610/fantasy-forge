-- preferred_analyst_lean
-- Grain: one row per (league_id, player_id) -- LIVE 2026 ONLY, joined against player_values'
-- projection_season = 2026 board. This is deliberately NOT folded into player_values/vorp: VORP
-- stays a pure, auditable model-driven number (replacement level + shrinkage-weighted
-- projections); this model surfaces where your preferred analysts (Cummings/Eisenberg/Gibbs --
-- whoever has rows in stg_analysts__draft_rankings) diverge from it, as a separate signal for
-- draft-day judgment calls, not a correction to be blended in.
--
-- WHY NOT 2021-2025 TOO: analyst_draft_rankings_2026 is a single manually-collected snapshot for
-- the 2026 draft, not a season-keyed history -- there is no equivalent data for the backtest
-- folds, and joining it in unscoped would silently apply 2026 draft opinions to a 2022 VORP
-- board. Restricting to projection_season = 2026 is the same discipline player_values.sql
-- documents for player_status.
--
-- ANALYST RANK NORMALIZATION: analysts don't all publish the same kind of rank, so each is
-- converted to a per-(analyst, position) ordinal before averaging:
--   * position_rank, where the source gives one directly (Eisenberg's per-position tier pages)
--   * else derived from overall_rank (Gibbs' single 1-175 board) via row_number within position
--   * else derived from tier alone (Cummings' QB/RB/TE tiers have no numeric rank) via
--     row_number(order by tier) -- this only orders TIERS correctly, not players within a tier;
--     that's the real granularity of a tier-based source and shouldn't be oversold as more
--     precise than it is.
-- n_analysts is carried through so a lean built from 3 analysts isn't confused with one from 1.
--
-- lean = model's position_rank (from VORP) minus the preferred-analyst average position_rank.
-- POSITIVE lean = your preferred analysts rank the player BETTER than the model does (model's
-- rank number is larger/worse); NEGATIVE = the model likes the player more than they do.

with analyst_ranks as (

    select
        analyst,
        player_id,
        position,
        case
            when position_rank is not null then position_rank
            when overall_rank is not null
                then row_number() over (partition by analyst, position order by overall_rank)
            else row_number() over (partition by analyst, position order by tier, player_id)
        end as analyst_position_rank
    from {{ ref('stg_analysts__draft_rankings') }}
    where has_gsis_match

),

consensus as (

    select
        player_id,
        position,
        avg(analyst_position_rank) as preferred_analyst_position_rank,
        count(distinct analyst)    as n_analysts
    from analyst_ranks
    group by player_id, position

),

board as (

    select league_id, player_id, position, vorp, position_rank as model_position_rank
    from {{ ref('player_values') }}
    where projection_season = 2026

)

select
    b.league_id,
    b.player_id,
    b.position,
    b.vorp,
    b.model_position_rank,
    c.preferred_analyst_position_rank,
    c.n_analysts,
    b.model_position_rank - c.preferred_analyst_position_rank as lean
from board as b
join consensus as c
    on b.player_id = c.player_id
    and b.position = c.position
