-- Grain: (team, season) — one row per team per regular season
-- Source: stg_nflverse__team_stats (game-grain); filter: REG only
-- snap_counts: 2013+; pfr_advstats_rushing: 2018+ — earlier seasons will have NULLs for those columns

with team_game_stats as (

    -- excludes a known junk row: 1999 week 9 has team IS NULL with a garbage stat line
    select * from {{ ref('stg_nflverse__team_stats') }}
    where season_type = 'REG'
      and team is not null

),

-- MAX offense snaps per team/game = proxy for total team offensive plays that game
snap_game as (

    select
        team,
        season,
        week,
        max(offense_snaps) as team_offense_snaps
    from {{ ref('stg_nflverse__snap_counts') }}
    where game_type = 'REG'
    group by team, season, week

),

snap_season as (

    select
        team,
        season,
        sum(team_offense_snaps)                        as offense_snaps,
        round(avg(team_offense_snaps), 1)              as offense_snaps_per_game
    from snap_game
    group by team, season

),

-- Rushing yards before contact aggregated to team/season — OL proxy
pfr_rush_season as (

    select
        team,
        season,
        sum(rushing_yards_before_contact)              as rush_yards_before_contact,
        round(
            sum(rushing_yards_before_contact)::double
            / nullif(sum(carries), 0),
            2
        )                                              as rush_ybc_per_carry
    from {{ ref('stg_nflverse__pfr_advstats_rushing') }}
    where game_type = 'REG'
    group by team, season

),

aggregated as (

    select
        team,
        season,
        count(*)                                       as games_played,

        -- passing
        sum(pass_attempts)                             as pass_attempts,
        sum(completions)                               as completions,
        sum(passing_yards)                             as passing_yards,
        sum(passing_tds)                               as passing_tds,
        sum(passing_interceptions)                     as passing_interceptions,
        sum(sacks_suffered)                            as sacks_suffered,
        sum(passing_air_yards)                         as passing_air_yards,

        -- rushing
        sum(carries)                                   as carries,
        sum(rushing_yards)                             as rushing_yards,
        sum(rushing_tds)                               as rushing_tds,

        -- targets: the allocation pie for the downstream player-level model
        sum(targets)                                   as targets,
        sum(receptions)                                as receptions

    from team_game_stats
    group by team, season

)

select
    a.team,
    a.season,
    a.games_played,

    -- season totals
    a.pass_attempts,
    a.completions,
    a.passing_yards,
    a.passing_tds,
    a.passing_interceptions,
    a.sacks_suffered,
    a.passing_air_yards,
    a.carries,
    a.rushing_yards,
    a.rushing_tds,
    a.targets,
    a.receptions,

    -- snap counts (null before 2013)
    s.offense_snaps,
    s.offense_snaps_per_game,

    -- OL proxy: rushing yards before contact (null before 2018)
    p.rush_yards_before_contact,
    p.rush_ybc_per_carry,

    -- per-game rates
    round(a.pass_attempts::double    / a.games_played, 1)              as pass_attempts_per_game,
    round(a.passing_yards::double    / a.games_played, 1)              as passing_yards_per_game,
    round(a.passing_tds::double      / a.games_played, 2)              as passing_tds_per_game,
    round(a.passing_air_yards::double / a.games_played, 1)             as passing_air_yards_per_game,
    round(a.carries::double          / a.games_played, 1)              as carries_per_game,
    round(a.rushing_yards::double    / a.games_played, 1)              as rushing_yards_per_game,
    round(a.rushing_tds::double      / a.games_played, 2)              as rushing_tds_per_game,
    round(a.targets::double          / a.games_played, 1)              as targets_per_game,

    -- efficiency rates
    round(a.completions::double      / nullif(a.pass_attempts, 0), 3)  as completion_pct,
    round(a.passing_tds::double      / nullif(a.pass_attempts, 0), 4)  as pass_td_rate,
    round(a.rushing_tds::double      / nullif(a.carries, 0), 4)        as rush_td_rate,
    round(a.rushing_yards::double    / nullif(a.carries, 0), 2)        as rush_ypc,
    round(a.passing_air_yards::double / nullif(a.targets, 0), 1)       as air_yards_per_target,
    round(a.passing_air_yards::double / nullif(a.pass_attempts, 0), 1) as air_yards_per_attempt

from aggregated as a
left join snap_season as s on s.team = a.team and s.season = a.season
left join pfr_rush_season as p on p.team = a.team and p.season = a.season
