"""Fit the RB/WR/TE auction-price concentration exponent (gamma) against real CBS
Consensus auction $ values, via log-log OLS: log(price) ~ gamma * log(vorp).

QB is deliberately excluded -- CBS's sheet assumes a standard 1-QB league and carries
no superflex signal, so it can't calibrate our superflex QB pricing. See
dbt/models/analytics/player_auction_prices.sql for how this fitted gamma is used.

Re-run this whenever dbt/seeds/cbs_consensus_auction_values.csv is refreshed with a
materially different sheet, and update GAMMA_NONQB in player_auction_prices.sql if the
fitted value moves.

Usage (from the main checkout):
    python scripts/fit_auction_gamma.py
"""

import duckdb
import numpy as np

QUERY = """
select pv.position, pv.vorp, av.auction_value_dollar as price
from analytics.player_values pv
join staging.stg_analysts__auction_values av on av.player_id = pv.player_id
where pv.league_id = 'coolplace'
  and pv.projection_season = 2026
  and pv.player_status = 'ACT'
  and pv.position != 'QB'
  and pv.vorp > 0
  and av.auction_value_dollar > 0
"""


def main():
    con = duckdb.connect("data/ff_platform.duckdb", read_only=True)
    df = con.execute(QUERY).fetch_df()
    con.close()

    x = np.log(df["vorp"].to_numpy())
    y = np.log(df["price"].to_numpy())
    gamma, intercept = np.polyfit(x, y, 1)
    pred = np.exp(intercept) * df["vorp"].to_numpy() ** gamma
    r2 = np.corrcoef(np.log(pred), y)[0, 1] ** 2

    print(f"pooled RB/WR/TE: n={len(df)} gamma={gamma:.3f} r2={r2:.3f}")
    for pos, g in df.groupby("position"):
        gx = np.log(g["vorp"].to_numpy())
        gy = np.log(g["price"].to_numpy())
        pg, pi = np.polyfit(gx, gy, 1)
        pp = np.exp(pi) * g["vorp"].to_numpy() ** pg
        pr2 = np.corrcoef(np.log(pp), gy)[0, 1] ** 2
        print(f"  {pos}: n={len(g)} gamma={pg:.3f} r2={pr2:.3f}")


if __name__ == "__main__":
    main()
