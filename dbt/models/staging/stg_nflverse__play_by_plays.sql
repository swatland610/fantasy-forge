with source as (
    select * from {{ source('nflverse', 'pbp') }}
),

renamed as (
    select
        -- ===== IDENTIFIERS =====
        play_id,
        game_id,
        season,
        week,

        -- ===== GAME CONTEXT =====
        game_date,
        home_team,
        away_team,
        posteam,
        defteam,
        posteam_type,

        -- ===== PLAY SITUATION =====
        qtr,
        down,
        ydstogo,
        yardline_100,
        goal_to_go,
        play_type,

        -- ===== PASSING =====
        passer_player_id,
        passer_player_name,
        passing_yards,
        air_yards,
        yards_after_catch,
        pass_attempt,
        complete_pass,
        incomplete_pass,
        interception,
        sack,

        -- ===== RUSHING =====
        rusher_player_id,
        rusher_player_name,
        rushing_yards,
        rush_attempt,

        -- ===== RECEIVING =====
        receiver_player_id,
        receiver_player_name,
        receiving_yards,
        pass_attempt as is_target,
        complete_pass as is_reception,

        -- ===== TOUCHDOWNS =====
        touchdown,
        pass_touchdown,
        rush_touchdown,
        return_touchdown,
        td_player_id,
        td_player_name,

        -- ===== TURNOVERS =====
        fumble,
        fumble_lost,
        fumble_recovery_1_player_id,

        -- ===== TWO-POINT CONVERSIONS =====
        two_point_attempt,
        two_point_conv_result,

        -- ===== RED ZONE FLAGS =====
        yardline_100 <= 20 as is_redzone,
        yardline_100 <= 10 as is_goalline,

        -- ===== ADVANCED METRICS =====
        epa,
        wp,
        wpa,
        cpoe,

        -- ===== PLAY METADATA =====
        "desc" as play_description,
        play_clock,
        drive,
        series,
        series_success

    from source
    where 1 = 1
    and play_type is not null
)

select * from renamed
