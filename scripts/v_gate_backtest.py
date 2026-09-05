"""
V-GATE backtest: does the custom projection out-rank the FantasyPros superflex market (ECR)?

This is the gate the whole roadmap hangs on. For each preseason 2021-2025 it compares, against
ACTUAL season results in the boc scoring format:
  * MY MODEL    -- player_values (boc), ranked by projected points (per-position) and VORP (overall)
  * THE MARKET  -- stg_nflverse__ff_rankings, contemporaneous late-August redraft-superflex ECR

All three inputs are dbt-materialized; this script only joins them and computes metrics, so it is
re-runnable after any model change (`python scripts/v_gate_backtest.py`).

METHODOLOGY NOTES (surfaced, not hidden):
  * Fair head-to-head = the COMMON universe: players ranked by BOTH my model and ECR that also
    have an actual outcome. Different coverage is reported separately, not blended into the score.
  * Survivorship: actuals are real season totals for players who played >= 1 game. Players a ranker
    listed who then did not play (DNP) are reported as dropped-N per fold, not silently dropped.
    Injury luck adds symmetric noise to both rankers (neither predicts it), so it does not bias the
    relative comparison.
  * Spearman uses pandas rank-correlation (proper average-rank tie handling). ECR is lower-is-better,
    so ECR skill is reported as -corr(ecr, actual) to orient both rankers as higher = better.
  * Overall cross-position truth = ACTUAL VORP: actual points minus the actual replacement level
    (the demand-rank-th best actual scorer at each position, over EVERYONE who played -- rookies
    included -- so the replacement baseline is the real one, not the returning-player-only pool).
"""

import duckdb
import pandas as pd

DB = "/Users/sean/github/ff-data-platform/data/ff_platform.duckdb"
FOLDS = (2021, 2022, 2023, 2024, 2025)
TOP_N = 60  # top-heavy horizon (~6 startable rounds in a 10-team superflex league)

con = duckdb.connect(DB, read_only=True)

# ----------------------------------------------------------------------------------------------
# One row per (fold, player) over EVERYONE who played, with actual points + actual cross-position
# VORP, and the two rankers' predictions left-joined on (nullable where a ranker didn't list them).
# ----------------------------------------------------------------------------------------------
eval_df = con.execute(
    """
    with repl as (
        select distinct position, replacement_rank
        from analytics.replacement_levels
        where league_id = 'boc'
    ),
    actual_pool as (
        select
            season, player_id, position, games_played,
            fantasy_points as actual_points,
            row_number() over (partition by season, position order by fantasy_points desc) as act_pos_rank
        from analytics.fct_player_season_fantasy_points
        where format_name = 'boc' and games_played >= 1
    ),
    actual_repl as (
        select ap.season, ap.position, ap.actual_points as repl_points
        from actual_pool ap
        join repl r on r.position = ap.position and r.replacement_rank = ap.act_pos_rank
    ),
    actual as (
        select
            ap.season, ap.player_id, ap.position, ap.games_played, ap.actual_points,
            ap.actual_points - ar.repl_points as actual_vorp
        from actual_pool ap
        join actual_repl ar on ar.season = ap.season and ar.position = ap.position
    ),
    mine as (
        select
            projection_season as season, player_id,
            projected_points as my_points, vorp as my_vorp,
            is_projection_low_confidence
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
        a.actual_points, a.actual_vorp,
        m.my_points, m.my_vorp, m.is_projection_low_confidence,
        k.ecr
    from actual a
    left join mine m   on m.season = a.season and m.player_id = a.player_id
    left join market k on k.season = a.season and k.player_id = a.player_id
    """
).df()


def spearman(pred, actual):
    """Spearman = Pearson on ranks. pandas .rank() uses average-rank tie handling; the default
    .corr() is Pearson (numpy, no scipy needed). Returns NaN if < 3 paired points."""
    mask = pred.notna() & actual.notna()
    if mask.sum() < 3:
        return float("nan")
    return pred[mask].rank().corr(actual[mask].rank())


# ----------------------------------------------------------------------------------------------
# 1. Coverage + survivorship (dropped-N): players a ranker listed who did not play.
# ----------------------------------------------------------------------------------------------
print("=" * 78)
print("1. COVERAGE PER FOLD (common universe = ranked by BOTH model and ECR, played >=1)")
print("=" * 78)
cov_rows = []
for y in FOLDS:
    f = eval_df[eval_df.season == y]
    common = f[f.my_points.notna() & f.ecr.notna()]
    mine_dnp = con.execute(
        "select count(*) from analytics.player_values v "
        "where v.league_id='boc' and v.projection_season=? "
        "and v.player_id not in (select player_id from analytics.fct_player_season_fantasy_points "
        "  where season=? and format_name='boc' and games_played>=1)",
        [y, y],
    ).fetchone()[0]
    cov_rows.append(
        dict(fold=y, played=len(f), in_my_model=f.my_points.notna().sum(),
             in_ecr=f.ecr.notna().sum(), common=len(common), my_ranked_DNP=mine_dnp)
    )
print(pd.DataFrame(cov_rows).to_string(index=False))

# restrict the head-to-head to the common universe
common_all = eval_df[eval_df.my_points.notna() & eval_df.ecr.notna()].copy()
common_all["ecr_neg"] = -common_all["ecr"]  # orient so higher = better

# ----------------------------------------------------------------------------------------------
# 2. Per-position rank skill (Spearman of predicted vs actual points), model vs market.
# ----------------------------------------------------------------------------------------------
print("\n" + "=" * 78)
print("2. PER-POSITION RANK SKILL  (Spearman vs actual points; higher = better)")
print("=" * 78)
pos_rows = []
for y in FOLDS:
    for pos in ("QB", "RB", "WR", "TE"):
        g = common_all[(common_all.season == y) & (common_all.position == pos)]
        pos_rows.append(dict(
            fold=y, position=pos, n=len(g),
            model=spearman(g.my_points, g.actual_points),
            ecr=spearman(g.ecr_neg, g.actual_points),
        ))
pos_df = pd.DataFrame(pos_rows)
pos_df["model_wins"] = pos_df.model > pos_df.ecr
print("\n-- averaged across folds --")
avg = pos_df.groupby("position")[["model", "ecr"]].mean().round(3)
avg["model_minus_ecr"] = (avg.model - avg.ecr).round(3)
print(avg.to_string())
print("\n-- per fold --")
print(pos_df.round(3).to_string(index=False))

# ----------------------------------------------------------------------------------------------
# 3. Overall cross-position rank skill (Spearman vs actual VORP), model vs market.
# ----------------------------------------------------------------------------------------------
print("\n" + "=" * 78)
print("3. OVERALL CROSS-POSITION SKILL  (Spearman vs actual VORP; higher = better)")
print("=" * 78)
ov_rows = []
for y in FOLDS:
    g = common_all[common_all.season == y]
    ov_rows.append(dict(
        fold=y, n=len(g),
        model=spearman(g.my_vorp, g.actual_vorp),
        ecr=spearman(g.ecr_neg, g.actual_vorp),
    ))
ov_df = pd.DataFrame(ov_rows)
print(ov_df.round(3).to_string(index=False))
print(f"\nmean overall Spearman -- model: {ov_df.model.mean():.3f}   ecr: {ov_df.ecr.mean():.3f}")

# ----------------------------------------------------------------------------------------------
# 4. Top-heavy recall@N: of the players who actually finished top-N by VORP, how many were in
#    each ranker's predicted top-N? (the tier that actually decides drafts)
# ----------------------------------------------------------------------------------------------
print("\n" + "=" * 78)
print(f"4. TOP-HEAVY RECALL@{TOP_N}  (share of the actual top-{TOP_N} a ranker had in its own top-{TOP_N})")
print("=" * 78)
rec_rows = []
for y in FOLDS:
    g = common_all[common_all.season == y]
    actual_top = set(g.nlargest(TOP_N, "actual_vorp").player_id)
    mine_top = set(g.nlargest(TOP_N, "my_vorp").player_id)
    ecr_top = set(g.nsmallest(TOP_N, "ecr").player_id)
    rec_rows.append(dict(
        fold=y,
        model=round(len(actual_top & mine_top) / len(actual_top), 3),
        ecr=round(len(actual_top & ecr_top) / len(actual_top), 3),
    ))
rec_df = pd.DataFrame(rec_rows)
print(rec_df.to_string(index=False))
print(f"\nmean recall@{TOP_N} -- model: {rec_df.model.mean():.3f}   ecr: {rec_df.ecr.mean():.3f}")

# ----------------------------------------------------------------------------------------------
# 5. Calibration of the model's POINT levels (VORP needs levels, not just order). Model-only --
#    ECR carries no point projection. Bias = mean(projected - actual).
# ----------------------------------------------------------------------------------------------
print("\n" + "=" * 78)
print("5. MODEL CALIBRATION  (projected vs actual points, players the model ranked & who played)")
print("=" * 78)
cal = eval_df[eval_df.my_points.notna()].copy()
cal["err"] = cal.my_points - cal.actual_points
cal_df = cal.groupby("position").agg(
    n=("err", "size"),
    MAE=("err", lambda s: s.abs().mean()),
    bias=("err", "mean"),
).round(1)
print(cal_df.to_string())

# ----------------------------------------------------------------------------------------------
# VERDICT
# ----------------------------------------------------------------------------------------------
print("\n" + "=" * 78)
print("VERDICT")
print("=" * 78)
ov_win = ov_df.model.mean() >= ov_df.ecr.mean()
rec_win = rec_df.model.mean() >= rec_df.ecr.mean()
pos_win = (avg.model >= avg.ecr)
print(f"  overall VORP Spearman : model {ov_df.model.mean():.3f} vs ecr {ov_df.ecr.mean():.3f}  -> "
      f"{'MODEL' if ov_win else 'ECR'}")
print(f"  top-{TOP_N} recall       : model {rec_df.model.mean():.3f} vs ecr {rec_df.ecr.mean():.3f}  -> "
      f"{'MODEL' if rec_win else 'ECR'}")
print(f"  per-position wins     : model beats/ties ECR in "
      f"{int(pos_win.sum())}/4 positions ({', '.join(pos_win[pos_win].index)})")
