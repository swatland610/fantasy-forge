with source as (
    select * from {{ source('nflverse', 'snap_counts') }}
),

renamed as (
    select
        -- ===== IDENTIFIERS =====
        game_id,
        pfr_game_id,
        pfr_player_id,
        season,
        week,
        game_type,

        -- ===== PLAYER & TEAM =====
        player as player_name,
        position,
        team,
        opponent,

        -- ===== SNAP COUNTS =====
        offense_snaps,
        offense_pct,
        defense_snaps,
        defense_pct,
        st_snaps as special_teams_snaps,
        st_pct as special_teams_pct,

        -- ===== CALCULATED FIELDS =====
        offense_snaps + defense_snaps + st_snaps as total_snaps

    from source
    where 1 = 1
)

select * from renamed
