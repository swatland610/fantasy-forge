with player_game_stats as (
    select * from {{ ref('fct_player_game_stats') }}
),

receiving_games as (
    select
        -- ===== IDENTIFIERS =====
        player_id,
        game_id,
        season,
        week,
        season_type,

        -- ===== PLAYER INFO =====
        position,
        team,

        -- ===== GAME CONTEXT =====
        is_home_game,
        team_won,
        offense_snaps,
        offense_pct,

        -- ===== RECEIVING STATS =====
        targets,
        receptions,
        receiving_yards,
        receiving_tds,
        receiving_air_yards,
        receiving_yards_after_catch,
        receiving_first_downs,
        receiving_epa,
        target_share,
        air_yards_share,
        wopr,
        racr,

        -- ===== FANTASY =====
        fantasy_points_ppr,

        -- ===== DERIVED: EFFICIENCY =====
        case
            when targets > 0 then receiving_yards * 1.0 / targets
            else 0
        end as yards_per_target,
        case
            when targets > 0 then receptions * 1.0 / targets
            else 0
        end as catch_rate,

        -- ===== DERIVED: GAME SEQUENCING =====
        row_number() over (
            partition by player_id, season
            order by week
        ) as player_season_game_num

    from player_game_stats
    where 1 = 1
        and position in ('WR', 'RB', 'TE')
        and targets > 0
)

select * from receiving_games
