with source as (
    select * from {{ source('nflverse', 'player_stats') }}
),

renamed as (
    select
        -- ===== IDENTIFIERS =====
        player_id,
        player_name,
        player_display_name,
        season,
        week,
        season_type,

        -- ===== PLAYER INFO =====
        position,
        position_group,
        team,
        opponent_team,

        -- ===== PASSING =====
        completions,
        attempts as pass_attempts,
        passing_yards,
        passing_tds,
        passing_interceptions,
        sacks_suffered,
        sack_yards_lost,
        passing_air_yards,
        passing_yards_after_catch,
        passing_first_downs,
        passing_epa,
        passing_cpoe,
        passing_2pt_conversions,
        pacr,

        -- ===== RUSHING =====
        carries,
        rushing_yards,
        rushing_tds,
        rushing_fumbles,
        rushing_fumbles_lost,
        rushing_first_downs,
        rushing_epa,
        rushing_2pt_conversions,

        -- ===== RECEIVING =====
        receptions,
        targets,
        receiving_yards,
        receiving_tds,
        receiving_fumbles,
        receiving_fumbles_lost,
        receiving_air_yards,
        receiving_yards_after_catch,
        receiving_first_downs,
        receiving_epa,
        receiving_2pt_conversions,
        racr,
        target_share,
        air_yards_share,
        wopr,

        -- ===== KICKING =====
        fg_made,
        fg_att,
        fg_missed,
        fg_long,
        fg_pct,
        fg_made_0_19,
        fg_made_20_29,
        fg_made_30_39,
        fg_made_40_49,
        fg_made_50_59,
        fg_made_60_,
        pat_made,
        pat_att,
        pat_pct,

        -- ===== SPECIAL TEAMS =====
        special_teams_tds,
        punt_returns,
        punt_return_yards,
        kickoff_returns,
        kickoff_return_yards,

        -- ===== FANTASY POINTS (PRE-CALCULATED) =====
        fantasy_points,
        fantasy_points_ppr,

        -- ===== MEDIA =====
        headshot_url

    from source
    where 1 = 1
)

select * from renamed
