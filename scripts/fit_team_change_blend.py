"""Validate whether a NEW TEAM's positional volume (relative to league average) improves the
projection for players who changed teams -- the "Kenneth Walker problem": opportunity share in
proj_player_season_components.sql is a pure recency-weighted average of the player's OWN trailing
usage, which is silently stale when the player switches situations (trade, free agency, cut/sign).

Hypothesis: a team's positional run/pass VOLUME is a real scheme signal (a run-heavy team gives
its backfield more carries regardless of who's in it). So for team-changers, scaling the player's
own trailing per-game opportunity by (new_team_position_pool_per_game / league_avg_pool_per_game)
should predict their actual next-season per-game usage better than their own trailing rate alone.

This is NOT a role-assumption model (it doesn't guess who the "RB1" is) -- it only rescales the
player's established usage level by how much that offense feeds the position in aggregate.

Method: for every (target_season, player) where the player's team in target_season-1 differs from
their ACTUAL team in target_season (known historically, so this fits/validates -- it does not
predict team changes), compare:
  (a) own trailing per-game opportunity (3yr recency-weighted, same construction as production)
  (b) (a) rescaled by the new team's position-pool ratio
against the player's ACTUAL per-game opportunity in target_season. Report MAE and correlation
for both, per position, restricted to team-changers only.

Usage (from dbt/, since it reads the same duckdb the dbt project uses):
    python ../scripts/fit_team_change_blend.py
"""

import duckdb
import numpy as np

QUERY = """
with target_seasons as (
    select distinct season as target_season
    from core.fct_player_season_stats
    where season >= 2006
),

-- player's own trailing (3yr recency-weighted) per-game opportunity, same decay scheme as
-- proj_player_season_components.sql
window_seasons as (
    select
        ts.target_season,
        s.player_id,
        s.position,
        s.team,
        case ts.target_season - s.season when 1 then 1.0 when 2 then 0.667 when 3 then 0.333 else 0.0 end as decay,
        s.games_played, s.carries, s.targets, s.pass_attempts
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
        arg_max(team, target_season - 0) as prior_team,  -- placeholder, replaced below
        sum(decay) as w,
        sum(decay * games_played) as d_games,
        sum(decay * carries) as d_carries,
        sum(decay * targets) as d_targets,
        sum(decay * pass_attempts) as d_attempts
    from window_seasons
    group by target_season, player_id
),

-- prior team = team in target_season - 1 specifically (most recent season, not arg_max over window)
prior_team as (
    select target_season, player_id, team as prior_team
    from window_seasons
    where decay = 1.0
),

-- actual outcome in the target season
actual as (
    select season as target_season, player_id, team as new_team, games_played, carries, targets, pass_attempts
    from core.fct_player_season_stats
    where games_played >= 4  -- need a real sample of the new role, not a cameo
),

-- team-position pool per game, one row per (season, team, position): total volume / season length
season_length as (
    select distinct season, case when season >= 2021 then 17.0 else 16.0 end as games_in_season
    from core.fct_player_season_stats
),

team_pool as (
    select
        s.season, s.team, s.position,
        sum(s.carries) / sl.games_in_season as carries_pool_per_game,
        sum(s.targets) / sl.games_in_season as targets_pool_per_game,
        sum(s.pass_attempts) / sl.games_in_season as attempts_pool_per_game
    from core.fct_player_season_stats s
    join season_length sl using (season)
    group by s.season, s.team, s.position, sl.games_in_season
),

league_avg_pool as (
    select season, position,
        avg(carries_pool_per_game) as lg_carries_pool,
        avg(targets_pool_per_game) as lg_targets_pool,
        avg(attempts_pool_per_game) as lg_attempts_pool
    from team_pool
    group by season, position
),

joined as (
    select
        a.target_season,
        a.player_id,
        a.position,
        pt.prior_team,
        act.new_team,
        a.w,
        a.d_games,
        a.d_carries / nullif(a.d_games, 0) as own_carries_pg,
        a.d_targets / nullif(a.d_games, 0) as own_targets_pg,
        a.d_attempts / nullif(a.d_games, 0) as own_attempts_pg,
        act.carries / nullif(act.games_played, 0) as actual_carries_pg,
        act.targets / nullif(act.games_played, 0) as actual_targets_pg,
        act.pass_attempts / nullif(act.games_played, 0) as actual_attempts_pg,
        tp.carries_pool_per_game as new_team_carries_pool,
        tp.targets_pool_per_game as new_team_targets_pool,
        tp.attempts_pool_per_game as new_team_attempts_pool,
        lg.lg_carries_pool, lg.lg_targets_pool, lg.lg_attempts_pool
    from agg a
    join prior_team pt using (target_season, player_id)
    join actual act using (target_season, player_id)
    join team_pool tp
        on tp.season = a.target_season - 1 and tp.team = act.new_team and tp.position = a.position
    join league_avg_pool lg
        on lg.season = a.target_season - 1 and lg.position = a.position
    where pt.prior_team != act.new_team  -- team-changers only
      and a.w > 0
)

select * from joined
"""


def report(position, opp_col, actual_col, pool_col, lg_col, df):
    sub = df[df["position"] == position].copy()
    sub = sub.dropna(subset=[opp_col, actual_col, pool_col, lg_col])
    sub = sub[sub[lg_col] > 0]
    if len(sub) < 15:
        print(f"{position:<5} n={len(sub):<5} -- too few team-changers to fit")
        return

    own = sub[opp_col].values
    actual = sub[actual_col].values
    ratio = sub[pool_col].values / sub[lg_col].values
    adjusted = own * ratio

    mae_own = np.mean(np.abs(own - actual))
    mae_adj = np.mean(np.abs(adjusted - actual))
    r_own = np.corrcoef(own, actual)[0, 1]
    r_adj = np.corrcoef(adjusted, actual)[0, 1]

    print(f"{position:<5} n={len(sub):<5} "
          f"MAE own={mae_own:.2f} MAE adj={mae_adj:.2f}  "
          f"R own={r_own:.3f} R adj={r_adj:.3f}")


def main():
    con = duckdb.connect("../data/ff_platform.duckdb", read_only=True)
    df = con.execute(QUERY).fetch_df()
    con.close()

    print(f"total team-changer rows: {len(df)}\n")
    print("Comparing own-trailing-only vs team-pool-rescaled projection, actual next-season per-game usage:\n")
    report("RB", "own_carries_pg", "actual_carries_pg", "new_team_carries_pool", "lg_carries_pool", df)
    report("WR", "own_targets_pg", "actual_targets_pg", "new_team_targets_pool", "lg_targets_pool", df)
    report("TE", "own_targets_pg", "actual_targets_pg", "new_team_targets_pool", "lg_targets_pool", df)
    report("QB", "own_attempts_pg", "actual_attempts_pg", "new_team_attempts_pool", "lg_attempts_pool", df)


if __name__ == "__main__":
    main()
