"""Live Cool Place draft board.

Reads data/ff_platform.duckdb read-only and auto-refreshes. Run alongside
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
REFRESH_SECONDS = 5

BOARD_SQL = """
select
    dp.display_name as player,
    dp.team,
    pv.position,
    pv.vorp,
    pv.overall_rank as rank,
    pv.position_rank as pos_rank
from analytics.player_values pv
join core.dim_players dp on dp.player_id = pv.player_id
where pv.league_id = ?
  and pv.projection_season = 2026
  and pv.player_status = 'ACT'
  and not exists (
    select 1 from main.drafted_picks d
    where try_cast(d.sleeper_player_id as bigint) = dp.sleeper_id
  )
order by pv.vorp desc
limit 50
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-path", default="data/ff_platform.duckdb")
    parser.add_argument("--league-id", default=DEFAULT_LEAGUE_ID)
    parser.add_argument("--budget", type=int, default=DEFAULT_BUDGET)
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


args = parse_args()

st.set_page_config(page_title="Cool Place — Live Draft", layout="wide")
st.title("Cool Place — Live Draft Board")

con = connect_readonly(args.db_path)
try:
    budget_df = con.execute(BUDGET_SQL, [args.budget]).fetch_df()
    recent_df = con.execute(RECENT_PICKS_SQL).fetch_df()
    board_df = con.execute(BOARD_SQL, [args.league_id]).fetch_df()
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
            use_container_width=True,
            hide_index=True,
        )

with col2:
    st.subheader("Recently drafted")
    if recent_df.empty:
        st.info("No picks yet.")
    else:
        st.dataframe(recent_df, use_container_width=True, hide_index=True)

st.subheader("Best remaining players (VORP, undrafted)")
st.dataframe(board_df, use_container_width=True, hide_index=True, height=600)

st.caption(
    "Ranked by VORP, not the hand-tuned $ auction prices in the Obsidian "
    "draft-board note — those aren't in the warehouse (ad-hoc downstream calc, "
    "not a dbt model). Cross-reference the Sheet/Obsidian board for $ targets; "
    "use this for live 'who's still on the board' and budget tracking."
)

time.sleep(REFRESH_SECONDS)
st.rerun()
