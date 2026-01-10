with players as (
    select * 
    from {{ ref('stg_nflverse__players') }}
), 

ff_player_ids as (
    select * 
    from {{ ref('stg_nflverse__ff_playerids') }}
), 

final as (
    select 
    -- ===== PRIMARY IDENTIFIERS =====
    p.player_id,
    p.esb_id,
    p.pfr_id,
    p.pff_id,
    p.espn_id,
    f.sleeper_id, 
    f.cbs_id,

    -- ===== NAME FIELDS =====
    p.display_name,
    p.first_name,
    p.last_name,
    p.short_name,

    -- ===== POSITION =====
    p.position,
    p.position_group,
    p.ngs_position,
    p.pff_position,

    -- ===== PHYSICAL ATTRIBUTES =====
    p.height,
    p.weight,
    p.birth_date,

    -- ===== TEAM & STATUS =====
    p.team,
    p.status,
    p.jersey_number,

    -- ===== CAREER INFO =====
    p.rookie_season,
    p.last_season,
    p.years_of_experience,
    p.college_name,
    p.college_conference,

    -- ===== DRAFT INFO =====
    p.draft_year,
    p.draft_round,
    p.draft_pick,
    p.draft_team,

    -- ===== MEDIA =====
    p.headshot
    from players p 
    left join ff_player_ids f 
        on p.player_id = f.player_id 
)

select * from final 
