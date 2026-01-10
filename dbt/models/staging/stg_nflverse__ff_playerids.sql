with source as (
    select * 
    from {{ source('nflverse', 'ff_playerids') }}
), 

renamed as (
    select
    -- ==== IDs ====
    gsis_id as player_id,
    nfl_id,
    sleeper_id,
    cbs_id,
    pfr_id
    from source
    where gsis_id is not null
    qualify row_number() over (partition by gsis_id order by sleeper_id desc nulls last) = 1
)

select * from renamed 
