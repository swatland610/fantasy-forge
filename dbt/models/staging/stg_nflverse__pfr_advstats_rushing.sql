with source as (
    select * from {{ source('nflverse', 'pfr_advstats_rushing') }}
),

renamed as (
    select
        -- ===== IDENTIFIERS =====
        game_id,
        pfr_game_id,
        pfr_player_id,
        pfr_player_name,
        season,
        week,
        game_type,

        -- ===== TEAM =====
        team,
        opponent,

        -- ===== RUSHING =====
        carries,
        rushing_yards_before_contact,
        rushing_yards_before_contact_avg,
        rushing_yards_after_contact,
        rushing_yards_after_contact_avg,
        rushing_broken_tackles

    from source
    where 1 = 1
)

select * from renamed
