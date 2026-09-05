"""
V-GATE residual autopsy: WHICH missing signals explain why ECR out-ranks the projection?

The gate showed ECR wins on per-position ranking. The hypothesis is that this is an
INFORMATION deficit, not a math bug: our projection is autoregressive (a player's own past
production, recency-weighted + shrunk) and is structurally blind to anything that changed
between last season and this one. ECR experts price that change. This script tests which of
four cheaply-measurable signals -- all the model ignores -- our errors actually load on.

The four candidate signals (each is something ECR can see and the model cannot):
  * AGE              -- dim_players.birth_date -> age at the projection season (career arc)
  * THIN/STALE HIST  -- is_projection_low_confidence (1 yr of history, or didn't play prior yr)
  * PRIOR-YR MISSED  -- games_played in season N-1 (injury / availability proxy)
  * TEAM CHANGE      -- team in N-1 vs N differ (new role/offense the model can't see)

Two complementary cuts:
  CUT A  Calibration -- does the over-projection RESIDUAL (projected - actual points) load on
         each signal, by position? (where our point LEVELS break)
  CUT B  Disagreement -- where the model and ECR most disagree within a position, is ECR
         systematically right, and are those disagreements concentrated in the signal cohorts?
         (where our RANKING breaks -- the metric the gate actually failed on)

NULL handling (per guardrails): a missing signal is data. Players with no birth_date, or no
season N-1 row (didn't play prior year), are reported as a separate count, never silently
dropped or coalesced. Same join universe and Spearman convention as scripts/v_gate_backtest.py.
Re-runnable: `python scripts/v_gate_residual_autopsy.py`.
"""

import duckdb
import numpy as np
import pandas as pd

DB = "/Users/sean/github/ff-data-platform/data/ff_platform.duckdb"
FOLDS = (2021, 2022, 2023, 2024, 2025)
POSITIONS = ("QB", "RB", "WR", "TE")

con = duckdb.connect(DB, read_only=True)

# ----------------------------------------------------------------------------------------------
# One row per (fold, player) over the model-ranked universe who played, carrying actual points,
# the model's projected points, ECR (nullable), and the four candidate signals. Signals that
# can't be resolved (no birth_date, no prior-season row) are left NULL and surfaced, not dropped.
# ----------------------------------------------------------------------------------------------
eval_df = con.execute(
    """
    with team_by_season as (
        select season, player_id, team, games_played
        from core.fct_player_season_stats
    ),
    actual as (
        select season, player_id, position, games_played,
               fantasy_points as actual_points
        from analytics.fct_player_season_fantasy_points
        where format_name = 'boc' and games_played >= 1
    ),
    mine as (
        select projection_season as season, player_id,
               projected_points as my_points, is_projection_low_confidence
        from analytics.player_values
        where league_id = 'boc'
    ),
    market as (
        select projection_season as season, player_id, ecr
        from staging.stg_nflverse__ff_rankings
        where has_gsis_match
    )
    select
        a.season, a.player_id, a.position, a.games_played,
        a.actual_points, m.my_points, m.is_projection_low_confidence, k.ecr,
        -- AGE at the projection season (whole years). birth_date is VARCHAR; NULL when missing.
        case when p.birth_date is not null
             then a.season - year(try_cast(p.birth_date as date)) end as age,
        -- PRIOR-YEAR availability: games played in season N-1. NULL when no N-1 row (didn't play).
        prior.games_played as prior_games,
        -- TEAM CHANGE N-1 -> N. NULL when either team is unknown (e.g. didn't play prior year).
        case when prior.team is not null and curr.team is not null
             then (prior.team <> curr.team) end as team_changed
    from actual a
    inner join mine m       on m.season = a.season and m.player_id = a.player_id
    left  join market k     on k.season = a.season and k.player_id = a.player_id
    left  join core.dim_players p on p.player_id = a.player_id
    left  join team_by_season prior on prior.player_id = a.player_id and prior.season = a.season - 1
    left  join team_by_season curr  on curr.player_id  = a.player_id and curr.season  = a.season
    where a.season in (2021, 2022, 2023, 2024, 2025)
      and a.position in ('QB', 'RB', 'WR', 'TE')
    """
).df()

eval_df["resid"] = eval_df.my_points - eval_df.actual_points  # + = over-projection


def slope_corr(x, y):
    """OLS slope and Pearson r of y on x, ignoring NaN pairs. NaN if < 3 points."""
    m = x.notna() & y.notna()
    if m.sum() < 3:
        return float("nan"), float("nan"), int(m.sum())
    xv, yv = x[m].to_numpy(float), y[m].to_numpy(float)
    slope = np.polyfit(xv, yv, 1)[0]
    r = np.corrcoef(xv, yv)[0, 1]
    return slope, r, int(m.sum())


# ==============================================================================================
# CUT A -- does the over-projection RESIDUAL load on each signal, by position?
# ==============================================================================================
print("=" * 90)
print("CUT A. CALIBRATION RESIDUAL vs each signal  (resid = projected - actual; + = over-projected)")
print("=" * 90)

# --- continuous signals: age, prior_games --> OLS slope + Pearson r of resid on the signal ---
print("\n-- continuous signals (slope = pts of residual per unit of signal; r = correlation) --")
cont_rows = []
for pos in POSITIONS:
    g = eval_df[eval_df.position == pos]
    for sig in ("age", "prior_games"):
        s, r, n = slope_corr(g[sig], g["resid"])
        cont_rows.append(dict(position=pos, signal=sig, n=n, slope=round(s, 2), r=round(r, 3)))
print(pd.DataFrame(cont_rows).to_string(index=False))

# age bucketed, so a nonlinear cliff (e.g. RB ~28) isn't hidden by a linear slope
print("\n-- mean residual by AGE bucket (nonlinear check) --")
age_bins = pd.cut(eval_df.age, [0, 24, 27, 30, 99], labels=["<=24", "25-27", "28-30", "31+"])
age_tab = eval_df.groupby([eval_df.position, age_bins], observed=True).agg(
    n=("resid", "size"), mean_resid=("resid", "mean")
).round(1)
print(age_tab.to_string())

# --- binary signals: low-confidence, team-change --> group mean residual + the gap ---
print("\n-- binary signals (mean residual within group; gap = True - False) --")
bin_rows = []
for pos in POSITIONS:
    g = eval_df[eval_df.position == pos]
    for sig in ("is_projection_low_confidence", "team_changed"):
        sub = g[g[sig].notna()]
        grp = sub.groupby(sig)["resid"].agg(["size", "mean"])
        t = grp.loc[True, "mean"] if True in grp.index else float("nan")
        f = grp.loc[False, "mean"] if False in grp.index else float("nan")
        nt = int(grp.loc[True, "size"]) if True in grp.index else 0
        nf = int(grp.loc[False, "size"]) if False in grp.index else 0
        bin_rows.append(dict(position=pos, signal=sig, n_true=nt, n_false=nf,
                             resid_true=round(t, 1), resid_false=round(f, 1),
                             gap=round(t - f, 1)))
print(pd.DataFrame(bin_rows).to_string(index=False))

# NULL accounting -- how much of each signal we simply can't resolve
print("\n-- signal coverage (NULLs are surfaced, not dropped) --")
n = len(eval_df)
cov = {
    "age_missing": int(eval_df.age.isna().sum()),
    "prior_games_missing (no N-1 row)": int(eval_df.prior_games.isna().sum()),
    "team_changed_unknown": int(eval_df.team_changed.isna().sum()),
    "ecr_missing (not market-ranked)": int(eval_df.ecr.isna().sum()),
    "total_rows": n,
}
for k, v in cov.items():
    print(f"  {k:36s} {v}")


# ==============================================================================================
# CUT B -- where model and ECR most disagree within a position, is ECR right, and on whom?
# ==============================================================================================
print("\n" + "=" * 90)
print("CUT B. DISAGREEMENT: when the model and ECR diverge within position, who's right -- and on whom?")
print("=" * 90)

# within-position ranks (1 = best) for model points, ECR, and ACTUAL points -- common universe only
common = eval_df[eval_df.ecr.notna() & eval_df.my_points.notna()].copy()
common["my_rank"] = common.groupby(["season", "position"])["my_points"].rank(ascending=False, method="average")
common["ecr_rank"] = common.groupby(["season", "position"])["ecr"].rank(ascending=True, method="average")
common["act_rank"] = common.groupby(["season", "position"])["actual_points"].rank(ascending=False, method="average")

# who was closer to the truth on this player?
common["err_model"] = (common.my_rank - common.act_rank).abs()
common["err_ecr"] = (common.ecr_rank - common.act_rank).abs()
common["ecr_better"] = common.err_ecr < common.err_model
# how far apart the two rankers were on this player (the disagreement magnitude)
common["disagree"] = (common.my_rank - common.ecr_rank).abs()

# focus on the players where the two rankers most diverge: top-quartile disagreement per pos-fold
common["big_disagree"] = common.groupby(["season", "position"])["disagree"].transform(
    lambda s: s >= s.quantile(0.75)
)

print("\n-- on the BIG-DISAGREEMENT players (top quartile per pos-fold): does ECR win, and is the "
      "model bullish or bearish vs ECR? --")
bd = common[common.big_disagree]
dis_rows = []
for pos in POSITIONS:
    g = bd[bd.position == pos]
    if len(g) == 0:
        continue
    # model_bullish = model ranks the player better (lower) than ECR did
    model_bullish = g.my_rank < g.ecr_rank
    dis_rows.append(dict(
        position=pos, n=len(g),
        ecr_wins_pct=round(g.ecr_better.mean(), 3),
        n_model_bullish=int(model_bullish.sum()),
        ecr_wins_when_model_bullish=round(g[model_bullish].ecr_better.mean(), 3),
        ecr_wins_when_model_bearish=round(g[~model_bullish].ecr_better.mean(), 3),
    ))
print(pd.DataFrame(dis_rows).to_string(index=False))

print("\n-- are the big-disagreement players over-represented in each signal cohort? "
      "(cohort rate among big-disagree vs the rest) --")
sig_rows = []
for sig, flagfn, label in [
    ("team_changed", lambda d: d.team_changed == True, "team_changed"),
    ("is_projection_low_confidence", lambda d: d.is_projection_low_confidence == True, "low_confidence"),
    ("prior_games", lambda d: d.prior_games <= 12, "prior_games<=12 (missed time)"),
    ("age", lambda d: d.age >= 30, "age>=30"),
]:
    base = common[common[sig].notna()]
    bd_rate = flagfn(base[base.big_disagree]).mean()
    rest_rate = flagfn(base[~base.big_disagree]).mean()
    # of the big-disagree players IN this cohort, how often does ECR win?
    cohort_bd = base[base.big_disagree & flagfn(base)]
    sig_rows.append(dict(
        signal=label,
        rate_big_disagree=round(bd_rate, 3),
        rate_rest=round(rest_rate, 3),
        lift=round(bd_rate - rest_rate, 3),
        n_cohort_bd=len(cohort_bd),
        ecr_wins_in_cohort=round(cohort_bd.ecr_better.mean(), 3) if len(cohort_bd) else float("nan"),
    ))
print(pd.DataFrame(sig_rows).to_string(index=False))

print("\nNOTES: team_changed collapses multi-team N-1 seasons to the last/primary team (possible "
      "false positives). 'ecr_wins' is a within-position rank-accuracy comparison on the common "
      "universe only. Slopes/means pool all 5 folds for n; per-position not per-fold.")
