with raw_player_stats as (
    select * 
    from {{ ref('stg_nflverse__player_stats') }}
), 

players as (
    select * 
    from {{ ref('dim_players') }}
), 

games as (
    select * 
    from {{ ref('dim_games') }}
),

snap_counts as (
    select * 
    from {{ ref('stg_nflverse__snap_counts') }}
),

player_stats as (
    select
        -- ===== IDENTIFIERS =====
        player_id,
        season,
        week,
        season_type,

        -- ===== PLAYER INFO =====
        position,
        team,

        -- ===== PASSING =====
        completions,
        pass_attempts,
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
        fantasy_points_half

    from raw_player_stats
),

final as (
    select 
        p.*, 
        g.game_id, 
        sc.offense_snaps, 
        sc.offense_pct,
        pl.pfr_player_id,
        pl.sleeper_id, 
        pl.cbs_id,
        case when p.team = g.home_team then true else false end as is_home_game,
        case 
            when p.team = g.winning_team then true
            when g.is_tie then null  -- ties are neither win nor loss
            else false 
        end as team_won
    from player_stats p 
    left join players pl 
        on p.player_id = pl.player_id
    left join snap_counts sc 
        on p.season = sc.season 
        and p.week = sc.week 
        and p.team = sc.team
        and pl.pfr_player_id = sc.pfr_player_id
    left join games g
        on p.season = g.season 
        and p.week = g.week 
        and (p.team = g.home_team or p.team = g.away_team)
    where 1 = 1 
    and p.position in ('QB', 'RB', 'WR', 'TE', 'K')
)

select * from final 
