with staging as (
    select * 
    from {{ ref('stg_nflverse__teams') }}
), 

final as (
    select 
            -- ===== IDENTIFIERS =====
        team_abbr,
        team_id,

        -- ===== TEAM INFO =====
        team_name,
        team_nickname,
        conference,
        division,
        conference || ' ' || division as conf_division,

        -- ===== BRANDING =====
        primary_color,
        secondary_color,
        logo_url,
        wordmark_url
    from staging
)

select * from final 
