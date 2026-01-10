with source as (
    select * 
    from {{ source('nflverse', 'schedules') }}
), 

renamed as (
    select 
    -- ==== Primary ID ====
        game_id, 

    -- ==== Game Info ====
        season, 
        week, 
        game_type, 
        gameday::date as game_date, 
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
       
       -- ==== Conditions ====
        roof, 
        surface, 
        temp, 
        wind, 
        stadium, 
        location

    from source
    where 1 = 1
)

select * from renamed 
