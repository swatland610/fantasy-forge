with source as (
    select * from {{ source('nflverse', 'team_stats') }}
),

renamed as (
    select
        -- ===== IDENTIFIERS =====
        season,
        week,
        season_type,
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

        -- ===== DEFENSE =====
        def_sacks,
        def_sack_yards,
        def_qb_hits,
        def_interceptions,
        def_interception_yards,
        def_pass_defended,
        def_tds,
        def_fumbles,
        def_fumbles_forced,
        def_safeties,
        def_tackles_solo,
        def_tackles_for_loss,

        -- ===== SPECIAL TEAMS =====
        special_teams_tds,
        punt_returns,
        punt_return_yards,
        kickoff_returns,
        kickoff_return_yards,

        -- ===== KICKING =====
        fg_made,
        fg_att,
        fg_pct,
        fg_long,
        pat_made,
        pat_att,

        -- ===== MISC =====
        penalties,
        penalty_yards,
        timeouts

    from source
    where 1 = 1
)

select * from renamed
