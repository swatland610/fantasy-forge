-- Grain: (projection_season, team) — one row per team per target season
-- Season-generalized: projection_season is a column over a spine of target seasons,
-- not a hardcoded year. Live board = projection_season 2026; prior years are backtest folds.
-- Method: recency-weighted (3-2-1 decay) per-game rates × 17. No shrinkage — teams always
-- play 17 games, so there is no sample-size variance to regress away (unlike player model).

{% set projection_seasons = var('projection_seasons', [2023, 2024, 2025, 2026]) %}

with season_spine as (

    select unnest([{{ projection_seasons | join(', ') }}]) as projection_season

),

window_seasons as (

    select
        sp.projection_season,
        t.team,
        t.season,
        case sp.projection_season - t.season
            when 1 then 1.0
            when 2 then 0.667
            when 3 then 0.333
            else 0.0
        end                as decay,
        t.games_played,
        t.pass_attempts,
        t.passing_yards,
        t.passing_tds,
        t.carries,
        t.rushing_yards,
        t.rushing_tds,
        t.targets
    from season_spine as sp
    join {{ ref('fct_team_season_stats') }} as t
        on t.season between sp.projection_season - 3 and sp.projection_season - 1

),

agg as (

    select
        projection_season,
        team,
        count(distinct season)         as seasons_of_history,

        sum(decay)                     as w_total,
        sum(decay * games_played)      as d_games,

        sum(decay * pass_attempts)     as d_pass_attempts,
        sum(decay * passing_yards)     as d_passing_yards,
        sum(decay * passing_tds)       as d_passing_tds,
        sum(decay * carries)           as d_carries,
        sum(decay * rushing_yards)     as d_rushing_yards,
        sum(decay * rushing_tds)       as d_rushing_tds,
        sum(decay * targets)           as d_targets

    from window_seasons
    group by projection_season, team

),

projected as (

    select
        projection_season,
        team,
        seasons_of_history,

        -- decay-weighted per-game rates; NULL when no history (surfaced, not coalesced)
        d_pass_attempts / nullif(d_games, 0)  as proj_pass_attempts_per_game,
        d_passing_yards / nullif(d_games, 0)  as proj_passing_yards_per_game,
        d_passing_tds   / nullif(d_games, 0)  as proj_passing_tds_per_game,
        d_carries       / nullif(d_games, 0)  as proj_carries_per_game,
        d_rushing_yards / nullif(d_games, 0)  as proj_rushing_yards_per_game,
        d_rushing_tds   / nullif(d_games, 0)  as proj_rushing_tds_per_game,
        d_targets       / nullif(d_games, 0)  as proj_targets_per_game

    from agg

)

select
    projection_season,
    team,
    seasons_of_history,

    -- per-game projections
    round(proj_pass_attempts_per_game, 1)  as proj_pass_attempts_per_game,
    round(proj_passing_yards_per_game, 1)  as proj_passing_yards_per_game,
    round(proj_passing_tds_per_game, 2)    as proj_passing_tds_per_game,
    round(proj_carries_per_game, 1)        as proj_carries_per_game,
    round(proj_rushing_yards_per_game, 1)  as proj_rushing_yards_per_game,
    round(proj_rushing_tds_per_game, 2)    as proj_rushing_tds_per_game,
    round(proj_targets_per_game, 1)        as proj_targets_per_game,

    -- projected season totals (× 17)
    round(proj_pass_attempts_per_game * 17, 0)  as proj_pass_attempts,
    round(proj_passing_yards_per_game * 17, 0)  as proj_passing_yards,
    round(proj_passing_tds_per_game * 17, 1)    as proj_passing_tds,
    round(proj_carries_per_game * 17, 0)        as proj_carries,
    round(proj_rushing_yards_per_game * 17, 0)  as proj_rushing_yards,
    round(proj_rushing_tds_per_game * 17, 1)    as proj_rushing_tds,
    round(proj_targets_per_game * 17, 0)        as proj_targets,

    -- derived totals
    round((proj_passing_yards_per_game + proj_rushing_yards_per_game) * 17, 0)  as proj_total_yards,
    round((proj_passing_tds_per_game + proj_rushing_tds_per_game) * 17, 1)      as proj_total_tds,

    dense_rank() over (
        partition by projection_season
        order by (proj_passing_yards_per_game + proj_rushing_yards_per_game) desc
    ) as offense_rank

from projected
order by projection_season, offense_rank
