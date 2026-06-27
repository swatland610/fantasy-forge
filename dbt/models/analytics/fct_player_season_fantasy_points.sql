-- fct_player_season_fantasy_points
-- Grain: one row per (season, player_id, format_name).
-- ACTUAL season fantasy points per scoring format -- the backtest's ground truth. Scores the
-- season-grain fact (fct_player_season_stats) against scoring_rules with the SAME UNPIVOT-and-join
-- machinery as proj_player_fantasy_points (V4), so projected and actual points are computed
-- identically. This symmetry is what makes "did the projection beat ECR?" a fair question.
--
-- WHY NOT just sum fct_fantasy_points (the game-grain scorer)? It predates the 'boc' format and
-- does not melt sacks_suffered, so its boc totals would silently omit the -1/sack penalty.
-- fct_player_season_stats carries sacks_suffered, so scoring it here keeps boc actuals complete.
--
-- position and games_played are carried through for the V-GATE harness (per-position correlation
-- and the dropped-N / minimum-games survivorship handling). Like V4, the inner join to
-- scoring_rules means unpriced stats contribute 0; no NULL coalescing.

with components as (

    select
        season,
        player_id,
        position,
        games_played,
        passing_yards,
        passing_tds,
        passing_interceptions,
        sacks_suffered,
        passing_2pt_conversions,
        rushing_yards,
        rushing_tds,
        rushing_2pt_conversions,
        rushing_fumbles_lost,
        rushing_first_downs,
        receptions,
        receiving_yards,
        receiving_tds,
        receiving_2pt_conversions,
        receiving_fumbles_lost,
        receiving_first_downs
    from {{ ref('fct_player_season_stats') }}
    where position in ('QB', 'RB', 'WR', 'TE')

),

stats_long as (

    -- melt wide component columns into (stat_name, stat_value) long form
    -- (season, player_id, position, games_played are kept as group columns)
    unpivot components
    on
        passing_yards,
        passing_tds,
        passing_interceptions,
        sacks_suffered,
        passing_2pt_conversions,
        rushing_yards,
        rushing_tds,
        rushing_2pt_conversions,
        rushing_fumbles_lost,
        rushing_first_downs,
        receptions,
        receiving_yards,
        receiving_tds,
        receiving_2pt_conversions,
        receiving_fumbles_lost,
        receiving_first_downs
    into
        name stat_name
        value stat_value

),

scored as (

    -- inner join keeps only stats priced in a given format; unpriced stats contribute 0
    select
        stats_long.season,
        stats_long.player_id,
        stats_long.position,
        stats_long.games_played,
        scoring_rules.format_name,
        sum(stats_long.stat_value * scoring_rules.points_per) as fantasy_points
    from stats_long
    inner join {{ ref('scoring_rules') }} as scoring_rules
        using (stat_name)
    group by 1, 2, 3, 4, 5

)

select
    season,
    player_id,
    position,
    games_played,
    format_name,
    round(fantasy_points, 1) as fantasy_points
from scored
