{{
    config(
        materialized='table'
    )
}}

with base as (
    select * from {{ ref('int_receiving__player_game_base') }}
    where 1 = 1
        and wopr is not null
        and isfinite(wopr)  -- filter out inf/nan values
),

position_season_stats as (
    select
        season,
        position,

        -- ===== SAMPLE SIZE =====
        count(*) as total_player_games,
        count(distinct player_id) as unique_players,

        -- ===== TARGETS =====
        avg(targets) as avg_targets,
        percentile_cont(0.5) within group (order by targets) as median_targets,
        percentile_cont(0.25) within group (order by targets) as p25_targets,
        percentile_cont(0.75) within group (order by targets) as p75_targets,
        stddev_pop(targets) as std_targets,

        -- ===== RECEPTIONS =====
        avg(receptions) as avg_receptions,
        percentile_cont(0.5) within group (order by receptions) as median_receptions,
        stddev_pop(receptions) as std_receptions,

        -- ===== RECEIVING YARDS =====
        avg(receiving_yards) as avg_receiving_yards,
        percentile_cont(0.5) within group (order by receiving_yards) as median_receiving_yards,
        percentile_cont(0.25) within group (order by receiving_yards) as p25_receiving_yards,
        percentile_cont(0.75) within group (order by receiving_yards) as p75_receiving_yards,
        stddev_pop(receiving_yards) as std_receiving_yards,

        -- ===== TARGET SHARE =====
        avg(target_share) as avg_target_share,
        percentile_cont(0.5) within group (order by target_share) as median_target_share,
        stddev_pop(target_share) as std_target_share,

        -- ===== WOPR =====
        avg(wopr) as avg_wopr,
        percentile_cont(0.5) within group (order by wopr) as median_wopr,
        stddev_pop(wopr) as std_wopr,

        -- ===== EFFICIENCY =====
        avg(yards_per_target) as avg_yards_per_target,
        stddev_pop(yards_per_target) as std_yards_per_target,
        avg(catch_rate) as avg_catch_rate,
        stddev_pop(catch_rate) as std_catch_rate,

        -- ===== EPA =====
        avg(receiving_epa) as avg_receiving_epa,
        stddev_pop(receiving_epa) as std_receiving_epa

    from base
    group by season, position
    having count(*) >= 10  -- need sufficient sample for meaningful baselines
)

select * from position_season_stats
