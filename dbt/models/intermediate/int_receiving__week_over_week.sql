with base as (
    select * from {{ ref('int_receiving__player_game_base') }}
),

with_lag as (
    select
        -- ===== IDENTIFIERS =====
        player_id,
        game_id,
        season,
        week,

        -- ===== CURRENT VALUES =====
        targets,
        receptions,
        receiving_yards,
        target_share,

        -- ===== PREVIOUS WEEK VALUES =====
        lag(targets) over (
            partition by player_id, season
            order by week
        ) as prev_week_targets,

        lag(receptions) over (
            partition by player_id, season
            order by week
        ) as prev_week_receptions,

        lag(receiving_yards) over (
            partition by player_id, season
            order by week
        ) as prev_week_receiving_yards,

        lag(target_share) over (
            partition by player_id, season
            order by week
        ) as prev_week_target_share

    from base
),

wow_changes as (
    select
        player_id,
        game_id,
        season,
        week,

        -- ===== ABSOLUTE CHANGES =====
        targets - prev_week_targets as wow_targets_change,
        receptions - prev_week_receptions as wow_receptions_change,
        receiving_yards - prev_week_receiving_yards as wow_receiving_yards_change,
        target_share - prev_week_target_share as wow_target_share_change,

        -- ===== PERCENTAGE CHANGES =====
        case
            when prev_week_targets > 0
            then (targets - prev_week_targets) * 1.0 / prev_week_targets
            else null
        end as wow_targets_pct_change,

        case
            when prev_week_receiving_yards > 0
            then (receiving_yards - prev_week_receiving_yards) * 1.0 / prev_week_receiving_yards
            else null
        end as wow_receiving_yards_pct_change,

        -- ===== MOMENTUM FLAGS =====
        targets > prev_week_targets as is_trending_up_targets,
        target_share > prev_week_target_share as is_trending_up_target_share

    from with_lag
    where prev_week_targets is not null  -- exclude first game of season
)

select * from wow_changes
