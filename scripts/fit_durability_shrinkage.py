"""Fit the reliability-weighted shrinkage constant (k) for projected_games, replacing the
PLACEHOLDER 0.75/0.25 fixed blend flagged in proj_player_season_components.sql.

Follows the exact methodology in docs/reliability-weighted-shrinkage.md, k ~ n_typical *
(1-R)/R, used for every other shrunk component (see dbt/seeds/shrinkage_constants.csv):

  1. Replicate the model's own trailing-window construction: for each (player, target
     season) pair, compute the SAME decay-weighted trailing average games/season
     (d_games / w_total, 3-2-1 decay over up to 3 prior seasons) the model already builds
     in proj_player_season_components.sql's `agg` CTE.
  2. Correlate that trailing average (the "observed" input to the blend) against the
     player's ACTUAL games played in the target season (the held-out outcome) -- this is
     the reliability R of the metric used elsewhere in the codebase.
  3. n (the shrinkage denominator) is w_total itself -- the SAME choice the codebase makes
     for every other component: n is always the decayed sum of the opportunity type
     underlying the observed rate (e.g. YPC's n is d_carries, the decayed carries behind
     rushing_yards/carries). Here the "opportunity" is a season, so n = w_total, the decayed
     season-count (max ~2.0 for full 3-year history).
  4. n_typical = the median w_total across the fitted sample (typical trailing evidence).
  5. k = n_typical * (1-R) / R.

Fit per position (QB/RB/WR/TE), since durability reliability plausibly differs by position
(e.g. QB injury risk vs. RB workload attrition).

Usage (from the main checkout):
    python scripts/fit_durability_shrinkage.py
"""

import duckdb
import numpy as np

DECAY_BY_LAG = {1: 1.0, 2: 0.667, 3: 0.333}

QUERY = """
with target_seasons as (
    select distinct season as target_season
    from core.fct_player_season_stats
    where season >= 2003  -- leave 3 prior seasons of runway from the 1999 data floor
),

window_seasons as (
    select
        ts.target_season,
        s.player_id,
        s.season,
        s.position,
        s.games_played,
        case ts.target_season - s.season when 1 then 1.0 when 2 then 0.667 when 3 then 0.333 else 0.0 end as decay
    from target_seasons ts
    join core.fct_player_season_stats s
        on s.season between ts.target_season - 3 and ts.target_season - 1
    where s.position in ('QB', 'RB', 'WR', 'TE')
),

trailing_window as (
    select
        target_season,
        player_id,
        arg_max(position, season) as position,
        sum(decay) as w_total,
        sum(decay * games_played) as d_games
    from window_seasons
    group by target_season, player_id
),

actual as (
    select season as target_season, player_id, games_played as actual_games
    from core.fct_player_season_stats
)

select
    t.position,
    t.w_total,
    t.d_games / nullif(t.w_total, 0) as trailing_avg_games,
    a.actual_games
from trailing_window t
join actual a
    on a.target_season = t.target_season and a.player_id = t.player_id
where t.w_total > 0
"""


def main():
    con = duckdb.connect("data/ff_platform.duckdb", read_only=True)
    df = con.execute(QUERY).fetch_df()
    con.close()

    print(f"total fitted rows: {len(df)}\n")
    print(f"{'position':<10}{'n':>8}{'R':>8}{'n_typical':>12}{'k':>10}")
    for pos, g in df.groupby("position"):
        r = np.corrcoef(g["trailing_avg_games"], g["actual_games"])[0, 1]
        n_typical = g["w_total"].median()
        k = n_typical * (1 - r) / r
        print(f"{pos:<10}{len(g):>8}{r:>8.3f}{n_typical:>12.3f}{k:>10.3f}")


if __name__ == "__main__":
    main()
