with source as (
    select * from {{ source('nflverse', 'teams') }}
),

renamed as (
    select
        -- ===== IDENTIFIERS =====
        team_abbr,
        team_id,

        -- ===== TEAM INFO =====
        team_name,
        team_nick as team_nickname,
        team_conf as conference,
        team_division as division,

        -- ===== BRANDING =====
        team_color as primary_color,
        team_color2 as secondary_color,
        team_logo_espn as logo_url,
        team_wordmark as wordmark_url

    from source
    where 1 = 1
)

select * from renamed
