-- Grain: (team, season) — one row per team per regular season
-- Source: stg_nflverse__team_stats (game-grain); filter: REG only
-- Totals + per-game rates; used as the source unit for proj_team_season_offense

with source as (

    select * from {{ ref('stg_nflverse__team_stats') }}
    where season_type = 'REG'

),

aggregated as (

    select
        team,
        season,
        count(*)                          as games_played,

        -- passing
        sum(pass_attempts)                as pass_attempts,
        sum(completions)                  as completions,
        sum(passing_yards)                as passing_yards,
        sum(passing_tds)                  as passing_tds,
        sum(passing_interceptions)        as passing_interceptions,
        sum(sacks_suffered)               as sacks_suffered,

        -- rushing
        sum(carries)                      as carries,
        sum(rushing_yards)                as rushing_yards,
        sum(rushing_tds)                  as rushing_tds,

        -- targets: the allocation pie for the downstream player-level model
        sum(targets)                      as targets,
        sum(receptions)                   as receptions

    from source
    group by team, season

)

select
    team,
    season,
    games_played,

    -- season totals
    pass_attempts,
    completions,
    passing_yards,
    passing_tds,
    passing_interceptions,
    sacks_suffered,
    carries,
    rushing_yards,
    rushing_tds,
    targets,
    receptions,

    -- per-game rates
    round(pass_attempts::double  / games_played, 1) as pass_attempts_per_game,
    round(passing_yards::double  / games_played, 1) as passing_yards_per_game,
    round(passing_tds::double    / games_played, 2) as passing_tds_per_game,
    round(carries::double        / games_played, 1) as carries_per_game,
    round(rushing_yards::double  / games_played, 1) as rushing_yards_per_game,
    round(rushing_tds::double    / games_played, 2) as rushing_tds_per_game,
    round(targets::double        / games_played, 1) as targets_per_game

from aggregated
