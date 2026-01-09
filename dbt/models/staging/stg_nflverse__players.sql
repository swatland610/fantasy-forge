with source as (
    select * from {{ source('nflverse', 'players') }}
),

renamed as (
    select
        -- ===== PRIMARY IDENTIFIERS =====
        gsis_id as player_id,
        esb_id,
        pfr_id,
        pff_id,
        espn_id,

        -- ===== NAME FIELDS =====
        display_name,
        first_name,
        last_name,
        short_name,

        -- ===== POSITION =====
        position,
        position_group,
        ngs_position,
        pff_position,

        -- ===== PHYSICAL ATTRIBUTES =====
        height,
        weight,
        birth_date,

        -- ===== TEAM & STATUS =====
        latest_team as team,
        status,
        jersey_number,

        -- ===== CAREER INFO =====
        rookie_season,
        last_season,
        years_of_experience,
        college_name,
        college_conference,

        -- ===== DRAFT INFO =====
        draft_year,
        draft_round,
        draft_pick,
        draft_team,

        -- ===== MEDIA =====
        headshot

    from source
    where 1 = 1
)

select * from renamed
