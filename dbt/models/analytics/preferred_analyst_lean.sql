-- preferred_analyst_lean
-- Grain: one row per (league_id, player_id) -- LIVE SEASON ONLY, joined against
-- player_values' most recent projection_season. This is deliberately NOT folded into
-- player_values/vorp: VORP stays a pure, auditable model-driven number (replacement level +
-- shrinkage-weighted projections); this model surfaces where your preferred analysts
-- (Cummings/Eisenberg/Gibbs -- whoever has rows in stg_analysts__draft_rankings) diverge
-- from it, as a separate signal for draft-day judgment calls, not a correction to be
-- blended in.
--
-- WHY NOT EVERY SEASON: analyst_draft_rankings_2026 is a single manually-collected snapshot
-- for the 2026 draft, not a season-keyed history -- there is no equivalent data for the
-- backtest folds, and joining it in unscoped would silently apply 2026 draft opinions to a
-- 2022 VORP board. Restricting to player_values' live season is the same discipline
-- player_values.sql documents for player_status. The live season is read from
-- max(projection_season) rather than hardcoded, so this doesn't go silently stale (empty
-- output, no error) the next time the live board rolls forward a year.
--
-- Per-analyst-source rank normalization (position_rank vs overall_rank vs tier-only) is
-- staging's job, not this model's -- see stg_analysts__draft_rankings.normalized_position_rank
-- and its header comment for how each source's format quirk is handled.
--
-- lean = model's position_rank (from VORP) minus the preferred-analyst average
-- normalized_position_rank. POSITIVE lean = your preferred analysts rank the player BETTER
-- than the model does (model's rank number is larger/worse); NEGATIVE = the model likes the
-- player more than they do.

with live_season as (

    select max(projection_season) as projection_season
    from {{ ref('player_values') }}

),

consensus as (

    select
        player_id,
        position,
        avg(normalized_position_rank) as preferred_analyst_position_rank,
        count(distinct analyst)       as n_analysts
    from {{ ref('stg_analysts__draft_rankings') }}
    where has_gsis_match
    group by player_id, position

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
    c.preferred_analyst_position_rank,
    c.n_analysts,
    b.model_position_rank - c.preferred_analyst_position_rank as lean
from board as b
join consensus as c
    on b.player_id = c.player_id
    and b.position = c.position
