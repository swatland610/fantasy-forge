---
title: Reliability-Weighted Shrinkage
tags: [projections, statistics, methodology, v-gate, v3]
status: reference
created: 2026-05-31
---

# Reliability-Weighted Shrinkage (`w = n / (n + k)`)

> **What this is:** the rule the projection uses to decide *how much to trust a player's own
> observed rate vs. how much to pull it back toward a baseline*, based on how much evidence
> (opportunity volume) we have. It's the core of Phase V3 in the projections roadmap.
>
> **One-liner:** `estimate = w·(player's observed rate) + (1−w)·(baseline)`, where
> `w = n / (n + k)`. `n` is the player's opportunity count; `k` is how many league-average
> observations the baseline is "worth."

---

## 1. The problem it solves

You observe a player's efficiency rate over `n` opportunities and want to estimate their
*true* rate going forward. Two naive options, both wrong:

- **Trust the observed rate fully.** A back with 6.8 yards/carry on 11 carries is almost
  certainly not a 6.8 YPC runner — tiny sample, the number is mostly noise.
- **Trust the position baseline fully.** A back with 4.9 YPC on 320 carries *genuinely is*
  better than average — ignoring that throws away real signal.

The right answer is a **blend**, and the blend weight should scale with **how much evidence
you have**. That is exactly what the formula does.

$$
\hat{\theta} \;=\; w\cdot \bar{x}_{\text{obs}} \;+\; (1-w)\cdot \mu_{\text{baseline}},
\qquad w = \frac{n}{n+k}
$$

| Symbol | Meaning | Example |
|---|---|---|
| $\bar{x}_{\text{obs}}$ | the player's observed rate | 6.8 YPC |
| $\mu_{\text{baseline}}$ | the (recency-weighted) position baseline | 4.3 YPC for RBs |
| $n$ | opportunity count (carries / targets / attempts) | 11 carries |
| $k$ | shrinkage constant — the prior's strength, in the **same units as `n`** | (fit per component) |
| $w$ | weight on the player's own number, between 0 and 1 | — |

---

## 2. Why *this* formula — it isn't arbitrary

`w = n/(n+k)` is the **posterior mean of a conjugate Bayesian model** (equivalently the
James–Stein / empirical-Bayes shrinkage estimator). It's what Bayes' rule *gives you* when
you blend a prior with binomial/normal evidence — not a heuristic someone eyeballed.

The cleanest derivation, for a rate like catch rate or completion % (Beta–Binomial):

Let true rate be $p$, with prior $p \sim \text{Beta}(\alpha, \beta)$. The prior mean is
$\mu = \frac{\alpha}{\alpha+\beta}$, and $\alpha+\beta$ acts as the prior's strength in
pseudo-observations. Observe $y$ successes in $n$ tries. The posterior is conjugate:

$$
p \mid y \sim \text{Beta}(\alpha + y,\; \beta + n - y),
\qquad
\hat{p} = \frac{\alpha + y}{\alpha + \beta + n}
$$

One line of algebra splits that estimate into its two sources:

$$
\hat{p}
= \underbrace{\frac{n}{n + (\alpha+\beta)}}_{w}\cdot \underbrace{\frac{y}{n}}_{\bar{x}_{\text{obs}}}
\;+\;
\underbrace{\frac{\alpha+\beta}{n+(\alpha+\beta)}}_{1-w}\cdot \underbrace{\frac{\alpha}{\alpha+\beta}}_{\mu_{\text{baseline}}}
$$

So **`k = α + β`** — literally the strength of the prior. The same shape holds for continuous
rates (YPC, yards/target) under a Normal–Normal model. The shrinkage estimator also provably
beats the raw observed rate on total mean-squared-error across a *population* of players (the
Stein result) — which is exactly our setting: we estimate hundreds of players at once.

---

## 3. What `k` actually means (the intuition to keep)

`k` is **the number of league-average observations the baseline is worth.** Read the weight
as a tug-of-war between two sample sizes:

- the player brings `n` real observations pulling toward their observed rate
- the baseline brings `k` pseudo-observations pulling toward the position mean

$$
w = \frac{n}{n+k} = \frac{\text{player's evidence}}{\text{player's evidence} + \text{prior's evidence}}
$$

**Break-even is `n = k`:** the volume at which you trust the player and the baseline equally
(50/50). Memorize this — when you're staring at the data, you can eyeball trust instantly:
"this guy has 2×k opportunities, so he's getting ~2/3 weight on his own number."

| Component | Reliability (year-over-year) | `k` | Behavior |
|---|---|---|---|
| completion %, target share | **high** (sticky) | **small** | believe the player's own number quickly |
| yards/target, yards/carry | medium | medium | needs a real sample |
| TD rate | **low** (noisy) | **large** | shrink hard; needs a huge sample to budge |

This is why **flat regression-to-the-mean is wrong** (and why the roadmap replaced it): a
fixed `w` for everyone over-shrinks the 320-carry workhorse (drags real signal back to the
mean) *and* under-shrinks the 11-carry fluke (lets noise through). The `n/(n+k)` form is
**self-adjusting** — same `k`, but `w` rises automatically with volume.

---

## 4. Behavior at the extremes (sanity checks)

$$
\lim_{n\to 0} w = 0 \;\Rightarrow\; \hat{\theta} = \mu_{\text{baseline}}
\qquad\text{(no data → pure baseline)}
$$
$$
\lim_{n\to\infty} w = 1 \;\Rightarrow\; \hat{\theta} = \bar{x}_{\text{obs}}
\qquad\text{(tons of data → pure observed)}
$$

A rookie / zero-opportunity player collapses cleanly to the position prior (no special-casing
needed); a full-season workhorse is trusted nearly as-is. The curve is **concave** — early
evidence is worth the most:

| `n` (carries) | `w` at `k = 200` | comment |
|---:|---:|---|
| 0 | 0.000 | pure baseline |
| 25 | 0.111 | barely trusted |
| 50 | 0.200 | |
| 100 | 0.333 | |
| 200 | 0.500 | **break-even (`n = k`)** |
| 300 | 0.600 | full-season RB |
| 400 | 0.667 | |
| 1000 | 0.833 | multi-season |

Going 25 → 50 carries moves `w` by ~0.09; going 300 → 325 moves it by ~0.01. Diminishing
returns on evidence, exactly as intuition says.

---

## 5. Worked examples (follow along)

> ⚠️ **The `k` values below are illustrative placeholders** to show the mechanics. The real
> per-component `k`s come out of the V-GATE stability analysis (see §6). Baselines shown are
> round numbers for arithmetic clarity, not fitted values.

### Example A — YPC: small-sample fluke vs. workhorse (`k = 200`, baseline `4.3`)

**Player A — 11 carries, 6.8 YPC** (a backup who broke one long run)

```
w   = 11 / (11 + 200) = 0.052
est = 0.052 × 6.8 + 0.948 × 4.3
    = 0.354 + 4.076
    = 4.43 YPC
```

The flashy 6.8 shrinks almost all the way back to baseline — correct, it was 11 carries.

**Player B — 320 carries, 4.9 YPC** (a true workhorse)

```
w   = 320 / (320 + 200) = 0.615
est = 0.615 × 4.9 + 0.385 × 4.3
    = 3.015 + 1.654
    = 4.67 YPC
```

Same baseline, same `k` — but B keeps most of his edge because he *earned* it over 320 carries.
**Note A's 6.8 ends up projected *below* B's 4.9.** That's the whole point: volume-weighted
trust, not raw-rate ranking.

---

### Example B — same player, two different `k`s (shows what `k` controls)

A WR with **50 targets, observed catch rate 0.70**, position baseline `0.63`.

**If catch rate is sticky (`k = 40`):**
```
w   = 50 / (50 + 40) = 0.556
est = 0.556 × 0.70 + 0.444 × 0.63 = 0.389 + 0.280 = 0.669
```

**If we (wrongly) treated it as noisy (`k = 400`):**
```
w   = 50 / (50 + 400) = 0.111
est = 0.111 × 0.70 + 0.889 × 0.63 = 0.078 + 0.560 = 0.638
```

Identical data, wildly different estimate (0.669 vs 0.638). **`k` is the entire ballgame** —
which is why we fit it from year-over-year reliability rather than guessing.

---

### Example C — Beta–Binomial directly (the `α/β` view)

Same WR, but using the prior-as-pseudo-counts framing. Baseline 0.63 with strength `k = 40`
means $\alpha = 0.63 \times 40 = 25.2$, $\beta = 0.37 \times 40 = 14.8$. Observe **35 catches
on 50 targets** (0.70):

```
posterior mean = (α + y) / (α + β + n)
               = (25.2 + 35) / (40 + 50)
               = 60.2 / 90
               = 0.669
```

Same 0.669 as Example B — confirming the "weighted average" and the "add pseudo-counts" views
are the same math. The pseudo-count view is often the more intuitive one when explaining it:
*you start the player with 25 imaginary catches on 40 imaginary targets, then add the real
ones.*

---

### Example D — TDs regress toward a *proxy*, not a flat mean

TD rate is the noisiest signal, so `k` is large — **but** the roadmap says don't shrink toward
a flat position mean; shrink toward an **expected-TD proxy** (goal-line carries, air yards /
WOPR). This doesn't change the formula at all — it only changes what $\mu_{\text{baseline}}$
*is*.

RB scored **14 rushing TDs on 9 actual goal-line carries** last year — observed TDs/carry is
sky-high and unsustainable. Suppose his expected-TD proxy (from goal-line volume) is `8.5 TDs`,
and we treat his ~50 red-zone/goal-line touches as the `n` against a large `k = 60`:

```
w   = 50 / (50 + 60) = 0.455
est = 0.455 × 14 + 0.545 × 8.5
    = 6.37 + 4.63
    = 11.0 projected TDs
```

The 14 regresses toward the volume-justified 8.5, landing at 11 — we don't fully believe the
spike, but we don't ignore that he *does* get goal-line work either. **Same `w = n/(n+k)`
machinery, smarter prior.**

---

## 6. How we set `k` from data (the V-GATE link)

`k` is **not guessed** — it's recovered from the **year-over-year reliability** of each
component, which is exactly what the V-GATE season-grain stability analysis measures on
`fct_player_season_stats`.

Regress season N+1 rate on season N rate (by position). The slope / correlation `R` tells you
how much signal persists. Standard empirical-Bayes result:

$$
k \;\approx\; n_{\text{typical}} \cdot \frac{1 - R}{R}
$$

- **sticky** component (target share, `R` high) → small `k` → trust players fast
- **noisy** component (TD rate, `R` low) → large `k` → shrink hard toward the proxy

So the stability correlations aren't *just* a "does the thesis hold" check — they **are the
calibration data that sets each component's `k`.** That's why the stability analysis runs
*before* V3.

### `k` table — fitted from the stability analysis (run 2026-06-02)

> Fitted on `fct_player_season_stats`, 1999–2025, year N→N+1 pairs with ≥8 games in both
> seasons and same player+position. `R` is the raw year-over-year Pearson correlation (a
> *lower bound* on true reliability — it folds in real change, so these `k`s shrink slightly
> harder, which is the conservative direction we want). `n_typ` = median opportunity among
> ≥8-game starters at that position. `k = round(n_typ · (1−R)/R)`. Query: `/tmp/stability.sql`
> + `/tmp/stability_opp.sql` (see roadmap V-GATE item #1).

**Efficiency — shrink each player's rate toward the recency-weighted position baseline:**

| Component | Pos | `R` | `n_typ` | **`k`** | read |
|---|---|---:|---:|---:|---|
| completion % | QB | 0.64 | 451 att | **255** | real skill — light shrink |
| yards/target | TE | 0.40 | 69 tgt | **105** | moderate |
| rush yards/carry | QB | 0.33 | 67 car | **135** | moderate |
| yards/target | WR | 0.29 | 84 tgt | **210** | needs a real sample |
| yards/carry | RB | 0.23 | 150 car | **510** | shrink hard |
| yards/target | RB | 0.08 | 57 tgt | **700** | ~noise — lean on volume, not rate |

**TD rates — shrink toward an *expected-TD proxy* (goal-line carries, air yards / WOPR), not a flat mean:**

| Component | Pos | `R` | `n_typ` | **`k`** | read |
|---|---|---:|---:|---:|---|
| pass TD rate | QB | 0.35 | 451 att | **850** | even QB pass-TD rate barely persists |
| rush TD rate | QB | 0.20 | 67 car | **265** | (don't over-shrink designed runners) |
| rush TD rate | RB | 0.17 | 150 car | **715** | a full season can't outvote the proxy |
| rec TD rate | WR | 0.16 | 84 tgt | **430** | regress almost entirely to proxy |
| rec TD rate | RB | 0.16 | 57 tgt | **305** | |
| rec TD rate | TE | 0.15 | 69 tgt | **395** | |

**Opportunity — sticky enough to lean on directly (recency-weight, don't reliability-shrink):**
the volume/share signals were all `R ≈ 0.6–0.8` for skill positions (WR target share 0.78,
RB carries/game 0.77, TE target share 0.75, QB rushing volume 0.84 — the single stickiest
metric, validating the designed-runner carve-out). These get **recency-weighted across the
last 1–3 seasons** rather than shrunk toward a position mean — the player *is* the signal.

> **Takeaway the numbers buy us:** opportunity is real and persistent → project it. Efficiency
> is mostly modest → shrink it. TD rates are noise → bury them in the proxy. The `k` spread
> (105 → 850) is exactly why a single flat shrinkage factor would have been wrong.

---

## 7. Gotchas / things to remember when reviewing the data

- **`n` is opportunities, not games.** Use carries/targets/attempts, not games played — a
  guy who played 17 games but got 30 targets still has a *small* receiving sample.
- **`n` and `k` must be in the same units.** `k` for YPC is in carries; `k` for catch rate is
  in targets. Don't mix.
- **Baseline must be season-rate and recency-weighted**, not the repo's existing game-grain,
  all-seasons-pooled means (`receiving_position_baselines`, `position_starter_stats`) — those
  are a different grain and pool 26 seasons flat.
- **NULL is not zero.** A player with zero targets has an *undefined* yards/target (NULL in
  `fct_player_season_stats`), which means `n = 0` → estimate collapses to baseline. Don't
  coalesce the NULL to 0 and feed it in as if observed — that's a silent bug.
- **Don't over-regress designed-runner QB rushing TDs.** Scheme, not luck — a large flat `k`
  would wrongly crush Jalen Hurts' tush-push TDs. This is a known carve-out in the roadmap.

---

## Related
- Roadmap: `.claude/plans/i-ve-done-a-mix-parsed-acorn.md` — Phase V3 (projection) & V-GATE
  (stability analysis that sets `k`)
- Source table: `dbt/models/core/fct_player_season_stats.sql` — the season-grain fact the
  stability analysis and projection both read
- Scoring config: `dbt/models/analytics/fct_fantasy_points.sql` — applied *after* components
  are projected
