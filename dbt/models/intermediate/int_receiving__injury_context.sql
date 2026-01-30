with base as (
    select * from {{ ref('int_receiving__player_game_base') }}
),

injuries as (
    select * from {{ ref('stg_nflverse__injuries') }}
),

-- Get player's own injury status
player_injuries as (
    select
        b.player_id,
        b.game_id,
        b.season,
        b.week,
        b.team,
        b.target_share,

        -- ===== PLAYER'S OWN INJURY STATUS =====
        coalesce(i.is_on_injury_report, false) as is_on_injury_report,
        coalesce(i.is_expected_out, false) as is_expected_out,
        i.report_status,
        i.practice_status

    from base b
    left join injuries i
        on b.player_id = i.gsis_id
        and b.season = i.season
        and b.week = i.week
),

-- Calculate returning from injury (was expected out last week, playing this week)
with_return_flag as (
    select
        *,
        case
            when lag(is_expected_out) over (
                partition by player_id, season
                order by week
            ) = true
            then true
            else false
        end as is_returning_from_injury
    from player_injuries
),

-- Get teammate injuries for opportunity calculation
teammate_injuries as (
    select
        b.player_id,
        b.game_id,
        b.season,
        b.week,
        b.team,

        -- Sum of target share from injured WR/TE teammates
        coalesce(sum(
            case
                when ti.is_expected_out = true
                    and teammate.position in ('WR', 'TE', 'RB')
                    and teammate.player_id != b.player_id
                then teammate.target_share
                else 0
            end
        ), 0) as team_wr_te_targets_available

    from base b
    -- Get all WR/TE teammates
    left join base teammate
        on b.team = teammate.team
        and b.season = teammate.season
        and b.week = teammate.week
        and b.player_id != teammate.player_id
    -- Check if teammate is injured
    left join injuries ti
        on teammate.player_id = ti.gsis_id
        and teammate.season = ti.season
        and teammate.week = ti.week
    group by 1, 2, 3, 4, 5
),

final as (
    select
        wrf.player_id,
        wrf.game_id,
        wrf.season,
        wrf.week,

        -- ===== PLAYER INJURY STATUS =====
        wrf.is_on_injury_report,
        wrf.is_expected_out,
        wrf.report_status,
        wrf.practice_status,
        wrf.is_returning_from_injury,

        -- ===== TEAMMATE OPPORTUNITY =====
        ti.team_wr_te_targets_available,
        ti.team_wr_te_targets_available > 0 as has_injured_teammate_opportunity

    from with_return_flag wrf
    left join teammate_injuries ti
        on wrf.player_id = ti.player_id
        and wrf.game_id = ti.game_id
)

select * from final
