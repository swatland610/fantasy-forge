with source as (
    select * from {{ source('nflverse', 'depth_charts') }}
),

renamed as (
    select
        -- ===== IDENTIFIERS =====
        gsis_id,
        season,
        week,
        game_type,

        -- ===== PLAYER INFO =====
        full_name,
        player_name,
        first_name,
        last_name,
        football_name,
        jersey_number,

        -- ===== TEAM & POSITION =====
        team,
        club_code,
        position,
        formation,

        -- ===== DEPTH CHART DETAILS =====
        depth_team,
        depth_position,
        pos_rank,
        pos_slot,
        pos_grp,
        pos_grp_id,
        pos_id,
        pos_name,
        pos_abb,

        -- ===== EXTERNAL IDS =====
        elias_id,
        espn_id,

        -- ===== METADATA =====
        dt,

        -- ===== DERIVED FIELDS =====
        depth_team = 1 as is_starter

    from source
    where 1 = 1
)

select * from renamed
