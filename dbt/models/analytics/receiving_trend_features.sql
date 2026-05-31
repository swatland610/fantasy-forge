{{
    config(
        materialized='table'
    )
}}

with base as (
    select * from {{ ref('int_receiving__player_game_base') }}
),

rolling as (
    select * from {{ ref('int_receiving__rolling_4game') }}
),

wow as (
    select * from {{ ref('int_receiving__week_over_week') }}
),

injury as (
    select * from {{ ref('int_receiving__injury_context') }}
),

final as (
    select
        -- ===== IDENTIFIERS =====
        b.player_id,
        b.game_id,
        b.season,
        b.week,
        b.player_season_game_num,

        -- ===== PLAYER INFO =====
        b.position,
        b.team,

        -- ===== GAME CONTEXT =====
        b.is_home_game,
        b.team_won,
        b.offense_snaps,
        b.offense_pct,

        -- ===== CURRENT GAME STATS =====
        b.targets,
        b.receptions,
        b.receiving_yards,
        b.receiving_tds,
        b.receiving_air_yards,
        b.receiving_yards_after_catch,
        b.receiving_first_downs,
        b.receiving_epa,
        b.target_share,
        b.air_yards_share,
        b.wopr,
        b.racr,
        b.fantasy_points_ppr,
        b.yards_per_target,
        b.catch_rate,

        -- ===== ROLLING FEATURES (prior 4 games) =====
        r.rolling_avg_targets,
        r.rolling_avg_receptions,
        r.rolling_avg_receiving_yards,
        r.rolling_avg_target_share,
        r.rolling_avg_wopr,
        r.rolling_avg_receiving_epa,
        r.rolling_avg_yards_per_target,
        r.rolling_avg_catch_rate,
        r.rolling_std_targets,
        r.rolling_games_played,

        -- ===== WEEK OVER WEEK FEATURES =====
        w.wow_targets_change,
        w.wow_receptions_change,
        w.wow_receiving_yards_change,
        w.wow_target_share_change,
        w.wow_targets_pct_change,
        w.wow_receiving_yards_pct_change,
        w.is_trending_up_targets,
        w.is_trending_up_target_share,

        -- ===== INJURY CONTEXT FEATURES =====
        i.is_on_injury_report,
        i.is_expected_out,
        i.report_status,
        i.practice_status,
        i.is_returning_from_injury,
        i.team_wr_te_targets_available,
        i.has_injured_teammate_opportunity,

        -- ===== DERIVED: CURRENT VS ROLLING =====
        b.targets - r.rolling_avg_targets as targets_vs_rolling_avg,
        b.target_share - r.rolling_avg_target_share as target_share_vs_rolling_avg,
        case
            when r.rolling_std_targets > 0
            then (b.targets - r.rolling_avg_targets) / r.rolling_std_targets
            else null
        end as targets_z_score

    from base b
    left join rolling r
        on b.player_id = r.player_id
        and b.game_id = r.game_id
    left join wow w
        on b.player_id = w.player_id
        and b.game_id = w.game_id
    left join injury i
        on b.player_id = i.player_id
        and b.game_id = i.game_id
)

select * from final
