"""Validate the durability-consistency hypothesis: does a player's own trailing-window
CONSISTENCY (variance of games_played across contributing seasons) predict how reliable
their durability record is, independent of how much evidence (volume) exists?

Motivation: the reliability_shrink() n/(n+k) formula only sees EVIDENCE VOLUME (agg.w_total),
never how consistent that evidence has been. A player with three straight 17-game seasons
(zero variance) is trusted at the exact same rate as a player with the same trailing MEAN but
wildly swinging season-to-season games (high variance) -- both look identical to a
volume-only shrinkage formula. See proj_player_season_components.sql's projected_games
column note for how this is applied.

Method: split the historical fit sample (same construction as
fit_durability_shrinkage.py) into low-variance ("consistent") and high-variance ("erratic")
halves by the position's median trailing-window variance, and compare the reliability
correlation R in each half. A meaningfully higher R for the consistent half validates using
variance as a real, data-grounded second signal (not just volume).

Usage (from the main checkout):
    python scripts/fit_durability_consistency.py
"""

import duckdb
import numpy as np

QUERY = """
with target_seasons as (
    select distinct season as target_season
    from core.fct_player_season_stats
    where season >= 2005
),

window_seasons as (
    select
        ts.target_season,
        s.player_id,
        s.position,
        s.games_played
    from target_seasons ts
    join core.fct_player_season_stats s
        on s.season between ts.target_season - 3 and ts.target_season - 1
    where s.position in ('QB', 'RB', 'WR', 'TE')
),

agg as (
    select
        target_season,
        player_id,
        arg_max(position, games_played) as position,
        count(*) as n_seasons,
        avg(games_played) as trail_mean,
        var_pop(games_played) as trail_var
    from window_seasons
    group by target_season, player_id
),

actual as (
    select season as target_season, player_id, games_played as actual_games
    from core.fct_player_season_stats
)

select a.position, a.trail_mean, a.trail_var, act.actual_games
from agg a
join actual act on act.target_season = a.target_season and act.player_id = a.player_id
where a.n_seasons >= 2
"""


def main():
    con = duckdb.connect("data/ff_platform.duckdb", read_only=True)
    df = con.execute(QUERY).fetch_df()
    con.close()

    print(f"total rows (n_seasons>=2): {len(df)}\n")
    print(f"{'position':<10}{'n':>8}{'median_var':>12}{'R(consistent)':>16}{'R(erratic)':>14}")
    for pos, g in df.groupby("position"):
        med = g["trail_var"].median()
        low = g[g["trail_var"] <= med]
        high = g[g["trail_var"] > med]
        r_low = np.corrcoef(low["trail_mean"], low["actual_games"])[0, 1]
        r_high = np.corrcoef(high["trail_mean"], high["actual_games"])[0, 1]
        print(f"{pos:<10}{len(g):>8}{med:>12.2f}{r_low:>16.3f}{r_high:>14.3f}")


if __name__ == "__main__":
    main()
