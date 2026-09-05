-- stg_analysts__auction_values
-- Grain: one row per cbs_id (CBS Sports' "Consensus CBS Fantasy Experts" PPR auction sheet).
-- Crosswalk is exact: cbs_id is CBS's own numeric player id, joined straight to
-- stg_nflverse__ff_playerids.cbs_id. No name normalization needed here, unlike
-- stg_analysts__draft_rankings -- confirmed 200/200 clean matches during initial load.
--
-- stg_nflverse__ff_playerids is NOT unique on cbs_id (a handful of cbs_ids map to two
-- distinct player_ids upstream) -- deduped here with a deterministic tiebreaker (lowest
-- player_id) so this model's own documented one-row-per-cbs_id grain actually holds,
-- rather than silently fanning out the next time a seed refresh happens to include one
-- of the affected ids.

with source as (

    select *
    from {{ ref('cbs_consensus_auction_values') }}

),

crosswalk as (

    select cbs_id, player_id
    from {{ ref('stg_nflverse__ff_playerids') }}
    where cbs_id is not null
    qualify row_number() over (partition by cbs_id order by player_id) = 1

)

select
    s.cbs_id,
    x.player_id,                          -- gsis id; NULL when unmatched (surfaced)
    (x.player_id is not null) as has_gsis_match,
    s.player_name_abbrev,
    s.position,
    s.bye_week,
    s.overall_rank,
    s.auction_value_dollar,
    s.source_url,
    s.pulled_date
from source as s
left join crosswalk as x
    on s.cbs_id = x.cbs_id
