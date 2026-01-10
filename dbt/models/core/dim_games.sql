with staging as (
    select * 
    from {{ ref('stg_nflverse__schedules') }}
), 

final as (
    select 
    -- ==== Primary ID ====
        game_id, 

    -- ==== Game Info ====
        season, 
        week, 
        game_type, 
        game_date, 
        weekday, 
        gametime, 
        home_team, 
        away_team, 
        home_rest,
        away_rest, 
        div_game, 

        -- ==== Result ====
        home_score, 
        away_score, 
        result,
        total, 
        overtime, 
        spread_line, 
        total_line, 
        home_score - away_score as home_margin,
        case 
            when home_score > away_score then home_team 
            when home_score < away_score then away_team 
            else null 
        end as winning_team,
        case 
            when home_score > away_score then away_team 
            when home_score < away_score then home_team 
            else null 
        end as losing_team,
        case when home_score = away_score then true else false end as is_tie,
       
       -- ==== Conditions ====
        roof, 
        surface, 
        temp, 
        wind, 
        stadium, 
        location
        
    from staging
)

select * from final 
