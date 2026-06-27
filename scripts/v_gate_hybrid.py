"""
V-GATE hybrid: does ECR's ordering + our format-aware VORP beat BOTH parents?

The gate (scripts/v_gate_backtest.py) showed the autoregressive projection loses to ECR on
per-position ranking, but the model has one edge ECR structurally lacks: it translates points
into FORMAT-AWARE, demand-aware cross-position value (VORP under boc's PPFD + superflex demand).
The residual autopsy (scripts/v_gate_residual_autopsy.py) traced the ranking loss to SITUATIONAL
signals ECR prices and the model can't see (team change, injury). Recovering those ourselves =
re-deriving the market. So the data-supported move is the HYBRID: let ECR supply the within-
position ORDER, keep our point SCALE + demand-aware VORP on top.

THE GRAFT (per fold, per position, on the common universe = model-projected AND ECR-ranked AND
played):
  1. sort the universe's MODEL projected points descending -> a fixed ladder of point values
  2. rank the same players by ECR (best = 1)
  3. assign ladder rung k to the ECR-#k player
=> hybrid_points[ECR rank k] = (k-th largest model projected points in that pos-fold).

Two consequences make this the MINIMAL HONEST hybrid, not a new curve:
  * the per-position point MULTISET is unchanged, so replacement_points (e.g. WR42) is IDENTICAL
    to the model's -- we move which players sit above/below the baseline, never the baseline.
  * the hybrid's within-position ORDER == ECR's order, so its per-position Spearman EQUALS ECR's
    (printed as a sanity check). The hybrid can only differ from pure ECR on CROSS-POSITION VORP,
    where it gains our format-aware re-leveling. That isolates exactly what the hybrid adds.

Graded identically to the gate: same common universe, same actual-VORP truth (actual points minus
the demand-rank-th best ACTUAL scorer per position), same pandas Spearman (no scipy). Re-runnable:
`python scripts/v_gate_hybrid.py`. Materializes nothing -- it decides whether materializing is
justified.
"""

import duckdb
import numpy as np
import pandas as pd

DB = "/Users/sean/github/ff-data-platform/data/ff_platform.duckdb"
FOLDS = (2021, 2022, 2023, 2024, 2025)
POSITIONS = ("QB", "RB", "WR", "TE")
TOP_N = 60  # same top-heavy horizon as the gate (~6 startable rounds, 10-team superflex)

con = duckdb.connect(DB, read_only=True)

# ----------------------------------------------------------------------------------------------
# One row per (fold, player) over EVERYONE who played, carrying actual points + actual VORP (truth),
# the model's projected points/VORP, ECR (nullable), and the model's published positional
# replacement_points (the baseline the graft reuses unchanged). Mirrors v_gate_backtest's universe.
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
    proj_repl as (
        -- the model's published positional replacement points; the graft reuses it unchanged
        select projection_season as season, position, replacement_points
        from analytics.replacement_levels
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
        k.ecr,
        pr.replacement_points
    from actual a
    left join mine m      on m.season = a.season and m.player_id = a.player_id
    left join market k    on k.season = a.season and k.player_id = a.player_id
    left join proj_repl pr on pr.season = a.season and pr.position = a.position
    """
).df()

# ----------------------------------------------------------------------------------------------
# Build the hybrid on the COMMON universe (model-projected AND ECR-ranked AND played) -- the same
# head-to-head universe the gate scores on. Players missing either input can't be grafted; they
# are reported, not silently dropped.
# ----------------------------------------------------------------------------------------------
common = eval_df[eval_df.my_points.notna() & eval_df.ecr.notna()].copy()


def graft(group):
    """Assign the k-th largest MODEL projected-points to the ECR-#k player in this pos-fold."""
    ladder = np.sort(group.my_points.to_numpy(float))[::-1]      # point values, best first
    ecr_rank = group.ecr.rank(method="first").astype(int)         # 1 = best ECR (ties broken stably)
    group["hybrid_points"] = ladder[ecr_rank.to_numpy() - 1]
    return group


common = (
    common.groupby(["season", "position"], group_keys=False)
    .apply(graft)
    .reset_index(drop=True)
)
# hybrid VORP reuses the model's published positional replacement (baseline unchanged by the graft)
common["hybrid_vorp"] = common.hybrid_points - common.replacement_points


def spearman(pred, actual):
    """Spearman = Pearson on ranks (pandas average-rank ties, numpy corr, no scipy). NaN if <3."""
    mask = pred.notna() & actual.notna()
    if mask.sum() < 3:
        return float("nan")
    return pred[mask].rank().corr(actual[mask].rank())


# ==============================================================================================
# 0. Coverage -- how many players carry both inputs (graftable) vs only one.
# ==============================================================================================
print("=" * 82)
print("0. GRAFT COVERAGE PER FOLD (common = model-projected AND ECR-ranked AND played)")
print("=" * 82)
cov_rows = []
for y in FOLDS:
    f = eval_df[eval_df.season == y]
    cov_rows.append(dict(
        fold=y, played=len(f),
        in_model=int(f.my_points.notna().sum()),
        in_ecr=int(f.ecr.notna().sum()),
        common_grafted=int((f.my_points.notna() & f.ecr.notna()).sum()),
        model_only=int((f.my_points.notna() & f.ecr.isna()).sum()),
        ecr_only=int((f.my_points.isna() & f.ecr.notna()).sum()),
    ))
print(pd.DataFrame(cov_rows).to_string(index=False))

# ==============================================================================================
# 1. Per-position rank skill (Spearman vs actual points). Hybrid should EQUAL ECR by construction.
# ==============================================================================================
print("\n" + "=" * 82)
print("1. PER-POSITION RANK SKILL  (Spearman vs actual points; hybrid==ecr is the sanity check)")
print("=" * 82)
common["ecr_neg"] = -common.ecr
pos_rows = []
for y in FOLDS:
    for pos in POSITIONS:
        g = common[(common.season == y) & (common.position == pos)]
        pos_rows.append(dict(
            fold=y, position=pos, n=len(g),
            model=spearman(g.my_points, g.actual_points),
            ecr=spearman(g.ecr_neg, g.actual_points),
            hybrid=spearman(g.hybrid_points, g.actual_points),
        ))
pos_df = pd.DataFrame(pos_rows)
avg = pos_df.groupby("position")[["model", "ecr", "hybrid"]].mean().round(3)
print("\n-- averaged across folds --")
print(avg.to_string())

# ==============================================================================================
# 2. Overall cross-position skill (Spearman vs actual VORP). THE HEADLINE: can hybrid beat BOTH?
# ==============================================================================================
print("\n" + "=" * 82)
print("2. OVERALL CROSS-POSITION SKILL  (Spearman vs actual VORP; the metric the hybrid targets)")
print("=" * 82)
ov_rows = []
for y in FOLDS:
    g = common[common.season == y]
    ov_rows.append(dict(
        fold=y, n=len(g),
        model=spearman(g.my_vorp, g.actual_vorp),
        ecr=spearman(g.ecr_neg, g.actual_vorp),
        hybrid=spearman(g.hybrid_vorp, g.actual_vorp),
    ))
ov_df = pd.DataFrame(ov_rows)
print(ov_df.round(3).to_string(index=False))
print(f"\nmean overall VORP Spearman -- model: {ov_df.model.mean():.3f}   "
      f"ecr: {ov_df.ecr.mean():.3f}   hybrid: {ov_df.hybrid.mean():.3f}")

# ==============================================================================================
# 3. Top-heavy recall@N by VORP (the tier that decides drafts).
# ==============================================================================================
print("\n" + "=" * 82)
print(f"3. TOP-HEAVY RECALL@{TOP_N}  (share of the actual top-{TOP_N} VORP a ranker had in its top-{TOP_N})")
print("=" * 82)
rec_rows = []
for y in FOLDS:
    g = common[common.season == y]
    actual_top = set(g.nlargest(TOP_N, "actual_vorp").player_id)
    rec_rows.append(dict(
        fold=y,
        model=round(len(actual_top & set(g.nlargest(TOP_N, "my_vorp").player_id)) / len(actual_top), 3),
        ecr=round(len(actual_top & set(g.nsmallest(TOP_N, "ecr").player_id)) / len(actual_top), 3),
        hybrid=round(len(actual_top & set(g.nlargest(TOP_N, "hybrid_vorp").player_id)) / len(actual_top), 3),
    ))
rec_df = pd.DataFrame(rec_rows)
print(rec_df.to_string(index=False))
print(f"\nmean recall@{TOP_N} -- model: {rec_df.model.mean():.3f}   "
      f"ecr: {rec_df.ecr.mean():.3f}   hybrid: {rec_df.hybrid.mean():.3f}")

# ==============================================================================================
# VERDICT -- does the hybrid beat (or tie) BOTH parents on the cross-position metrics?
# ==============================================================================================
print("\n" + "=" * 82)
print("VERDICT  (hybrid is justified only if it >= BOTH parents on the cross-position metrics)")
print("=" * 82)
hy_ov, mo_ov, ec_ov = ov_df.hybrid.mean(), ov_df.model.mean(), ov_df.ecr.mean()
hy_rc, mo_rc, ec_rc = rec_df.hybrid.mean(), rec_df.model.mean(), rec_df.ecr.mean()
print(f"  overall VORP Spearman : hybrid {hy_ov:.3f}  vs model {mo_ov:.3f} / ecr {ec_ov:.3f}  -> "
      f"hybrid {'WINS/TIES' if hy_ov >= max(mo_ov, ec_ov) else 'LOSES'}")
print(f"  top-{TOP_N} recall       : hybrid {hy_rc:.3f}  vs model {mo_rc:.3f} / ecr {ec_rc:.3f}  -> "
      f"hybrid {'WINS/TIES' if hy_rc >= max(mo_rc, ec_rc) else 'LOSES'}")
print("\nNOTE: per-position hybrid == ecr by construction (graft inherits ECR's within-position "
      "order); the hybrid's whole bet is cross-position VORP, so that's where the verdict is read.")
