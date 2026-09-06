"""Live Cool Place draft board.

Reads data/ff_platform.duckdb read-only. The board/budget/recent-picks section
auto-refreshes on its own (st.fragment); the player lookup below it is a plain
interactive section that doesn't get reset by that refresh. Run alongside
draft_poller.py, which keeps main.drafted_picks current from Sleeper.

Usage (from the main checkout):
    uv run streamlit run scripts/streamlit_app.py
"""

import argparse
import sys
import time

import duckdb
import pandas as pd
import streamlit as st

DEFAULT_LEAGUE_ID = "coolplace"
DEFAULT_BUDGET = 250
DEFAULT_SEASON = 2026
REFRESH_SECONDS = 5

# CBS doesn't document what budget their "Auction Value" column assumes (checked both
# the rankings page and their auction-values page directly -- neither states it). Inferred
# from the numbers instead: max value is $35 (top overall), and a true #1 overall typically
# sells for 25-35% of budget in real drafts. $35 as 17.5% of a $200 budget would be unusually
# cheap; $35 as 35% of a $100 budget matches typical real-draft behavior much better. Treat
# this as an inference, not a confirmed fact -- adjust if it looks wrong once real bids come
# in.
CBS_BUDGET_SCALE = DEFAULT_BUDGET / 100

# CBS's sheet is a standard 1-QB league, so QB $ there reflects standard demand (~12
# startable QBs), not our superflex demand (~22 startable, 24 rostered). Budget-size
# scaling alone doesn't fix that -- it's a demand-curve mismatch, not just a dollar-scale
# one. Proxy: rescale CBS's *aggregate* QB budget share to match our real superflex QB
# share (23.4%, the same demand-derived number player_auction_prices.sql uses), without
# touching their player-to-player order. CBS's own QB share, computed from their sheet:
# sum(QB $) / sum(all $) = 78/1194 = 6.53%. Ratio = 0.234 / 0.0653 = 3.58x, on top of the
# $100->$250 budget-size scale above.
#
# Caveat: this only corrects the aggregate level, not the curve SHAPE -- CBS's QB spread
# is much flatter (top value $35, near-replacement ~$0) than our own gamma-concentrated
# superflex curve, since standard leagues don't bother differentiating deep QBs. Sanity
# check: this proxy puts Josh Allen at ~$116, above our own model's $74 ceiling for him.
# Read it as a rough magnitude check on aggregate QB spend, not a literal per-player bid
# target -- our own player_auction_prices.auction_price is still the number to draft from.
CBS_QB_SHARE = 78 / 1194
QB_SUPERFLEX_SHARE = 0.234  # same constant as player_auction_prices.sql
QB_SCARCITY_RATIO = QB_SUPERFLEX_SHARE / CBS_QB_SHARE

BOARD_SQL = """
select
    dp.display_name as player,
    dp.team,
    pv.position,
    ap.auction_price as price,
    pv.vorp,
    pv.overall_rank as rank,
    pv.position_rank as pos_rank,
    lean.lean as analyst_lean,
    lean.n_analysts
from analytics.player_values pv
join core.dim_players dp on dp.player_id = pv.player_id
left join analytics.player_auction_prices ap on ap.player_id = pv.player_id
left join analytics.preferred_analyst_lean lean
    on lean.player_id = pv.player_id and lean.league_id = pv.league_id
where pv.league_id = ?
  and pv.projection_season = ?
  and pv.player_status = 'ACT'
  and not exists (
    select 1 from main.drafted_picks d
    where try_cast(d.sleeper_player_id as bigint) = dp.sleeper_id
  )
order by ap.auction_price desc nulls last, pv.vorp desc
limit 60
"""

BUDGET_SQL = """
select
    roster_id,
    count(*) as picks_made,
    coalesce(sum(amount), 0) as spent,
    ? - coalesce(sum(amount), 0) as remaining
from main.drafted_picks
where roster_id is not null
group by roster_id
order by remaining asc
"""

RECENT_PICKS_SQL = """
select pick_no, round, roster_id, player_name, position, team, amount, is_keeper
from main.drafted_picks
order by pick_no desc
limit 15
"""

PLAYER_LIST_SQL = """
select dp.player_id, dp.display_name, dp.team, pv.position
from analytics.player_values pv
join core.dim_players dp on dp.player_id = pv.player_id
where pv.league_id = ?
  and pv.projection_season = ?
  and pv.player_status = 'ACT'
order by pv.vorp desc
"""

PLAYER_DETAIL_SQL = """
select
    dp.display_name,
    dp.team,
    dp.college_name,
    dp.years_of_experience,
    pv.position,
    pv.vorp,
    pv.overall_rank,
    pv.position_rank,
    ap.auction_price,
    cbs.auction_value_dollar as cbs_price,
    fp.fantasy_points as proj_fantasy_points,
    pc.projected_games,
    pc.proj_carries,
    pc.rushing_yards,
    pc.rushing_tds,
    pc.proj_targets,
    pc.receptions,
    pc.receiving_yards,
    pc.receiving_tds,
    pc.proj_pass_attempts,
    pc.passing_completions,
    pc.passing_yards,
    pc.passing_tds,
    pc.passing_interceptions,
    mock.pick_no as superflex_mock_pick,
    mock.extraction_flagged as superflex_mock_flagged
from core.dim_players dp
join analytics.player_values pv
    on pv.player_id = dp.player_id and pv.league_id = ? and pv.projection_season = ?
left join analytics.player_auction_prices ap on ap.player_id = dp.player_id
left join staging.stg_analysts__auction_values cbs on cbs.player_id = dp.player_id
left join analytics.proj_player_fantasy_points fp
    on fp.player_id = dp.player_id and fp.projection_season = ? and fp.format_name = 'half_ppr'
left join analytics.proj_player_season_components pc
    on pc.player_id = dp.player_id and pc.projection_season = ?
left join staging.stg_superflex_mock__qb_capital mock
    on mock.player_id = dp.player_id and mock.has_gsis_match
where dp.player_id = ?
"""

ANALYST_RANKS_SQL = """
select analyst, normalized_position_rank as position_rank, tier, overall_rank
from staging.stg_analysts__draft_rankings
where player_id = ? and has_gsis_match
order by analyst
"""

QB_SUPERFLEX_MOCK_SQL = """
select
    dp.display_name as player,
    mock.pick_no,
    pv.overall_rank as our_overall_rank,
    pv.vorp,
    ap.auction_price as price,
    mock.extraction_flagged
from staging.stg_superflex_mock__qb_capital mock
join core.dim_players dp on dp.player_id = mock.player_id
left join analytics.player_values pv
    on pv.player_id = mock.player_id and pv.league_id = ? and pv.projection_season = ?
left join analytics.player_auction_prices ap on ap.player_id = mock.player_id
where mock.has_gsis_match
order by mock.pick_no
"""

# Position-appropriate projected-stat columns, in display order.
POSITION_STAT_COLUMNS = {
    "QB": [
        ("proj_pass_attempts", "pass att"),
        ("passing_completions", "completions"),
        ("passing_yards", "pass yds"),
        ("passing_tds", "pass td"),
        ("passing_interceptions", "int"),
        ("rushing_yards", "rush yds"),
        ("rushing_tds", "rush td"),
    ],
    "RB": [
        ("proj_carries", "carries"),
        ("rushing_yards", "rush yds"),
        ("rushing_tds", "rush td"),
        ("proj_targets", "targets"),
        ("receptions", "rec"),
        ("receiving_yards", "rec yds"),
        ("receiving_tds", "rec td"),
    ],
    "WR": [
        ("proj_targets", "targets"),
        ("receptions", "rec"),
        ("receiving_yards", "rec yds"),
        ("receiving_tds", "rec td"),
    ],
    "TE": [
        ("proj_targets", "targets"),
        ("receptions", "rec"),
        ("receiving_yards", "rec yds"),
        ("receiving_tds", "rec td"),
    ],
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-path", default="data/ff_platform.duckdb")
    parser.add_argument("--league-id", default=DEFAULT_LEAGUE_ID)
    parser.add_argument("--budget", type=int, default=DEFAULT_BUDGET)
    parser.add_argument("--season", type=int, default=DEFAULT_SEASON)
    # Streamlit passes its own args through; only parse ours, ignore the rest.
    args, _ = parser.parse_known_args(sys.argv[1:])
    return args


def connect_readonly(db_path: str, retries: int = 5, delay: float = 0.3) -> duckdb.DuckDBPyConnection:
    last_err = None
    for _ in range(retries):
        try:
            return duckdb.connect(db_path, read_only=True)
        except duckdb.IOException as e:
            last_err = e
            time.sleep(delay)
    raise last_err


def style_remaining(val):
    if val < 30:
        return "color: #ff657a"  # red — nearly tapped out
    if val < 80:
        return "color: #ffd76d"  # yellow — getting tight
    return "color: #bad761"  # green — plenty left


def style_lean(val):
    if pd.isna(val):
        return ""
    if val >= 15:
        return "color: #bad761"  # your analysts like this player a lot more than the model
    if val <= -15:
        return "color: #ff657a"  # your analysts like this player a lot less than the model
    return ""


args = parse_args()

st.set_page_config(page_title="Cool Place — Live Draft", layout="wide")
st.title("Cool Place — Live Draft Board")


@st.cache_data(ttl=300)
def load_player_list(db_path: str, league_id: str, season: int) -> pd.DataFrame:
    con = connect_readonly(db_path)
    try:
        return con.execute(PLAYER_LIST_SQL, [league_id, season]).fetch_df()
    finally:
        con.close()


@st.fragment(run_every=REFRESH_SECONDS)
def live_board():
    con = connect_readonly(args.db_path)
    try:
        budget_df = con.execute(BUDGET_SQL, [args.budget]).fetch_df()
        recent_df = con.execute(RECENT_PICKS_SQL).fetch_df()
        board_df = con.execute(BOARD_SQL, [args.league_id, args.season]).fetch_df()
    finally:
        con.close()

    st.caption(f"Auto-refreshing every {REFRESH_SECONDS}s · budget/team ${args.budget}")

    col1, col2 = st.columns([1, 1])

    with col1:
        st.subheader("Budget remaining by roster")
        if budget_df.empty:
            st.info("No picks yet.")
        else:
            st.dataframe(
                budget_df.style.map(style_remaining, subset=["remaining"]),
                width="stretch",
                hide_index=True,
            )

    with col2:
        st.subheader("Recently drafted")
        if recent_df.empty:
            st.info("No picks yet.")
        else:
            st.dataframe(recent_df, width="stretch", hide_index=True)

    st.subheader("Best remaining players (undrafted)")
    st.dataframe(
        board_df.style.map(style_lean, subset=["analyst_lean"]),
        width="stretch",
        hide_index=True,
        height=650,
        column_config={
            "price": st.column_config.NumberColumn("price ceiling", format="$%d"),
            "analyst_lean": st.column_config.NumberColumn(
                "analyst lean",
                help="Your preferred analysts' avg position rank minus the model's. "
                "Positive = they like this player more than VORP does.",
            ),
            "n_analysts": st.column_config.NumberColumn(
                "# analysts", help="How many of your analysts ranked this player"
            ),
        },
    )

    st.caption(
        "Price ceiling: $250-budget auction model — QB keeps the original hand-anchored "
        "gamma (no superflex market data to fit against); RB/WR/TE is fit against real CBS "
        "Consensus auction $ (moderate fit, r²≈0.33 — a calibrated estimate, not a verified "
        "one). Only ~90 players clear replacement level and get priced; everyone else is an "
        "implied $1 fill. Analyst lean: Cummings/Eisenberg/Gibbs vs. the model — see "
        "dbt/models/analytics/player_auction_prices.sql and preferred_analyst_lean.sql for "
        "the full methodology."
    )


live_board()

st.divider()
st.subheader("Player lookup")

player_list_df = load_player_list(args.db_path, args.league_id, args.season)
player_options = {
    f"{row.display_name} ({row.position}, {row.team})": row.player_id
    for row in player_list_df.itertuples()
}
selected_label = st.selectbox(
    "Search a player",
    options=list(player_options.keys()),
    index=None,
    placeholder="Type a name…",
    label_visibility="collapsed",
)

if selected_label:
    player_id = player_options[selected_label]
    con = connect_readonly(args.db_path)
    try:
        detail = con.execute(
            PLAYER_DETAIL_SQL,
            [args.league_id, args.season, args.season, args.season, player_id],
        ).fetch_df()
        analyst_ranks = con.execute(ANALYST_RANKS_SQL, [player_id]).fetch_df()
    finally:
        con.close()

    if detail.empty:
        st.warning("No data for this player.")
    else:
        row = detail.iloc[0]

        st.markdown(f"### {row.display_name} · {row.position} · {row.team}")
        bio_bits = []
        if pd.notna(row.college_name):
            bio_bits.append(row.college_name)
        if pd.notna(row.years_of_experience):
            bio_bits.append(f"{int(row.years_of_experience)} yrs exp")
        if bio_bits:
            st.caption(" · ".join(bio_bits))

        m1, m2, m3, m4, m5 = st.columns(5)
        m1.metric("VORP", f"{row.vorp:.1f}" if pd.notna(row.vorp) else "—")
        m2.metric("Overall rank", int(row.overall_rank) if pd.notna(row.overall_rank) else "—")
        m3.metric("Position rank", int(row.position_rank) if pd.notna(row.position_rank) else "—")
        m4.metric("Price ceiling", f"${int(row.auction_price)}" if pd.notna(row.auction_price) else "—")
        is_qb = row.position == "QB"
        total_scale = CBS_BUDGET_SCALE * QB_SCARCITY_RATIO if is_qb else CBS_BUDGET_SCALE
        cbs_scaled = row.cbs_price * total_scale if pd.notna(row.cbs_price) else None
        if is_qb:
            cbs_help = (
                f"Raw CBS value ${row.cbs_price:.0f}, scaled {CBS_BUDGET_SCALE:.2f}x for "
                f"budget size and {QB_SCARCITY_RATIO:.2f}x for superflex QB scarcity "
                "(CBS's own QB budget share, 6.5%, rescaled to our real superflex share, "
                "23.4%). Corrects the aggregate level only, not CBS's flatter curve shape — "
                "treat as a rough magnitude check, not a bid target. Use the price ceiling "
                "for actual bids."
            )
        else:
            cbs_help = (
                f"Raw CBS value ${row.cbs_price:.0f} scaled {CBS_BUDGET_SCALE:.2f}x, "
                "inferred (not confirmed) to assume a $100 budget from top-pick pricing "
                "patterns."
            )
        m5.metric(
            "CBS $ (scaled)",
            f"${cbs_scaled:.0f}" if cbs_scaled is not None else "—",
            help=cbs_help if pd.notna(row.cbs_price) else "No CBS Consensus value for this player.",
        )

        if is_qb and pd.notna(row.superflex_mock_pick):
            flagged = " ⚠️" if row.superflex_mock_flagged else ""
            st.caption(
                f"Superflex mock draft capital: pick {int(row.superflex_mock_pick)}{flagged} "
                "— from a single real 12-team superflex mock (12 different drafters), not a "
                "stated ranking. Real revealed-preference superflex QB demand, since CBS's own "
                "$ sheet has none."
                + (" This pick has flagged extraction uncertainty — see the seed's notes." if row.superflex_mock_flagged else "")
            )

        proj_points = f"{row.proj_fantasy_points:.1f}" if pd.notna(row.proj_fantasy_points) else "—"
        st.markdown(f"**Projected 2026 fantasy points (half-PPR):** {proj_points}")
        if pd.notna(row.projected_games):
            st.caption(f"Projected games: {row.projected_games:.1f}")

        stat_cols = POSITION_STAT_COLUMNS.get(row.position, [])
        stat_data = {
            label: [row[col]]
            for col, label in stat_cols
            if col in row.index and pd.notna(row[col])
        }
        if stat_data:
            st.dataframe(pd.DataFrame(stat_data).round(1), width="stretch", hide_index=True)

        if not analyst_ranks.empty:
            st.markdown("**Your analysts' individual rankings**")
            st.dataframe(
                analyst_ranks,
                width="stretch",
                hide_index=True,
                column_config={
                    "position_rank": st.column_config.NumberColumn(
                        "position rank",
                        help="Normalized to position rank so all three analysts are "
                        "comparable — some sources only publish overall rank or a tier, "
                        "not a raw position rank.",
                    ),
                    "overall_rank": st.column_config.NumberColumn(
                        "overall rank (raw)",
                        help="Null when that analyst's source doesn't publish an overall rank.",
                    ),
                },
            )
        else:
            st.caption("None of your preferred analysts ranked this player.")

st.divider()
st.subheader("QB: our model vs. real superflex mock draft capital")
st.caption(
    "Single 12-team superflex mock (12 different drafters, real revealed-preference "
    "draft capital) vs. our own VORP/price. Useful for sanity-checking the model's QB "
    "order independent of our own pipeline — e.g. this is what surfaced Bo Nix ranking "
    "above Josh Allen in our model despite going 56 picks later here. n=1 mock, not a "
    "market consensus — ⚠️ marks picks with flagged extraction uncertainty."
)
qb_mock_con = connect_readonly(args.db_path)
try:
    qb_mock_df = qb_mock_con.execute(QB_SUPERFLEX_MOCK_SQL, [args.league_id, args.season]).fetch_df()
finally:
    qb_mock_con.close()

qb_mock_df["flag"] = qb_mock_df["extraction_flagged"].map(lambda x: "⚠️" if x else "")
st.dataframe(
    qb_mock_df.drop(columns=["extraction_flagged"]),
    width="stretch",
    hide_index=True,
    column_config={
        "pick_no": st.column_config.NumberColumn("mock pick"),
        "our_overall_rank": st.column_config.NumberColumn("our overall rank"),
        "price": st.column_config.NumberColumn("our price", format="$%d"),
        "flag": st.column_config.TextColumn(" ", help="Flagged extraction uncertainty — see the seed's notes"),
    },
)
