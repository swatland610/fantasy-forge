with base as (
    select * from {{ ref('int_receiving__player_game_base') }}
),

rolling_stats as (
    select
        -- ===== IDENTIFIERS =====
        player_id,
        game_id,
        season,
        week,

        -- ===== ROLLING AVERAGES (4 games, excluding current) =====
        avg(targets) over (
            partition by player_id, season
            order by week
            rows between 4 preceding and 1 preceding
        ) as rolling_avg_targets,

        avg(receptions) over (
            partition by player_id, season
            order by week
            rows between 4 preceding and 1 preceding
        ) as rolling_avg_receptions,

        avg(receiving_yards) over (
            partition by player_id, season
            order by week
            rows between 4 preceding and 1 preceding
        ) as rolling_avg_receiving_yards,

        avg(target_share) over (
            partition by player_id, season
            order by week
            rows between 4 preceding and 1 preceding
        ) as rolling_avg_target_share,

        avg(wopr) over (
            partition by player_id, season
            order by week
            rows between 4 preceding and 1 preceding
        ) as rolling_avg_wopr,

        avg(receiving_epa) over (
            partition by player_id, season
            order by week
            rows between 4 preceding and 1 preceding
        ) as rolling_avg_receiving_epa,

        avg(yards_per_target) over (
            partition by player_id, season
            order by week
            rows between 4 preceding and 1 preceding
        ) as rolling_avg_yards_per_target,

        avg(catch_rate) over (
            partition by player_id, season
            order by week
            rows between 4 preceding and 1 preceding
        ) as rolling_avg_catch_rate,

        -- ===== ROLLING CONSISTENCY (std dev) =====
        stddev(targets) over (
            partition by player_id, season
            order by week
            rows between 4 preceding and 1 preceding
        ) as rolling_std_targets,

        -- ===== ROLLING GAME COUNT (for filtering early season) =====
        count(*) over (
            partition by player_id, season
            order by week
            rows between 4 preceding and 1 preceding
        ) as rolling_games_played

    from base
)

select * from rolling_stats
