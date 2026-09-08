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

BOARD_SQL = """
with heath_tiers as (
    -- Heath Cummings only, kept separate from preferred_analyst_lean's multi-analyst
    -- consensus -- this is his raw tier number, not a blended lean. group by/min()
    -- guards against a player somehow appearing twice under his byline.
    select player_id, min(tier) as heath_tier
    from staging.stg_analysts__draft_rankings
    where analyst = 'Heath Cummings' and has_gsis_match
    group by player_id
),

veterans as (
    select
        dp.display_name as player,
        dp.team,
        pv.position,
        ap.auction_price as price,
        pv.vorp,
        pv.overall_rank as rank,
        pv.position_rank as pos_rank,
        sml.mock_pick_no,
        sml.lean as mock_lean,
        ht.heath_tier,
        cast(null as varchar) as market_priced_reason
    from analytics.player_values pv
    join core.dim_players dp on dp.player_id = pv.player_id
    left join analytics.player_auction_prices ap on ap.player_id = pv.player_id
    left join analytics.superflex_mock_lean sml
        on sml.player_id = pv.player_id and sml.league_id = pv.league_id
    left join heath_tiers ht on ht.player_id = pv.player_id
    where pv.league_id = ?
      and pv.projection_season = ?
      and pv.player_status = 'ACT'
      and not exists (
        select 1 from main.drafted_picks d
        where try_cast(d.sleeper_player_id as bigint) = dp.sleeper_id
      )
      and not exists (
        select 1 from analytics.market_priced_player_values mp
        where mp.player_id = pv.player_id
      )
),

market_priced as (
    select
        dp.display_name as player,
        dp.team,
        r.position,
        r.estimated_price as price,
        cast(null as double) as vorp,
        cast(null as bigint) as rank,
        cast(null as bigint) as pos_rank,
        cast(null as bigint) as mock_pick_no,
        cast(null as bigint) as mock_lean,
        ht.heath_tier,
        r.reason as market_priced_reason
    from analytics.market_priced_player_values r
    join core.dim_players dp on dp.player_id = r.player_id
    left join heath_tiers ht on ht.player_id = r.player_id
    where not exists (
        select 1 from main.drafted_picks d
        where try_cast(d.sleeper_player_id as bigint) = dp.sleeper_id
    )
),

board_rows as (
    select * from veterans
    union all
    select * from market_priced
),

-- Select the top 60 by price/vorp first, THEN reorder for display by Heath's tier --
-- otherwise limiting after the display sort would only show his personal top tier,
-- not the same "best remaining players" universe the rest of the board expects.
ranked as (
    select
        *,
        case
            when price + coalesce(mock_lean, 0) > 0 then price + coalesce(mock_lean, 0)
            else 1
        end as price_adjusted
    from board_rows
    order by price desc nulls last, vorp desc
    limit 60
)

select * from ranked
order by heath_tier asc nulls last, vorp desc
"""

BUDGET_SQL = """
-- Sleeper mock drafts leave roster_id/picked_by null (no real league roster to
-- attach to) and only populate draft_slot, so fall back to that as the team key.
-- Mock drafts also expose no real team names, so label the viewer's own slot
-- 'You' and the rest generically by slot number.
select
    case when coalesce(roster_id, draft_slot) = ? then 'You'
         else 'Team ' || coalesce(roster_id, draft_slot)
    end as team,
    count(*) as picks_made,
    coalesce(sum(amount), 0) as spent,
    ? - coalesce(sum(amount), 0) as remaining
from main.drafted_picks
where coalesce(roster_id, draft_slot) is not null
group by coalesce(roster_id, draft_slot)
order by remaining asc
"""

# Target $ by position: reuses the same demand-weighted shares the price-ceiling
# model conserves across the full $3,000/12-team pool (see player_auction_prices.sql
# -- QB held at 23.4%, RB/WR/TE split by vorp^0.595), scaled down to one team's budget.
TARGET_BY_POSITION_SQL = """
select position, sum(auction_price) / 12.0 * (? / 250.0) as target
from analytics.player_auction_prices
group by position
"""

MY_SPEND_BY_POSITION_SQL = """
select position, coalesce(sum(amount), 0) as spent
from main.drafted_picks
where coalesce(roster_id, draft_slot) = ?
group by position
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
    sml.mock_pick_no as superflex_mock_pick,
    sml.mock_position_rank as superflex_mock_position_rank,
    sml.lean as superflex_mock_lean,
    sml.mock_extraction_flagged as superflex_mock_flagged,
    ov.override_games as durability_override_games,
    ov.reason as durability_override_reason,
    (
        select min(tier) from staging.stg_analysts__draft_rankings hd
        where hd.player_id = dp.player_id and hd.analyst = 'Heath Cummings' and hd.has_gsis_match
    ) as heath_tier
from core.dim_players dp
join analytics.player_values pv
    on pv.player_id = dp.player_id and pv.league_id = ? and pv.projection_season = ?
left join analytics.player_auction_prices ap on ap.player_id = dp.player_id
left join analytics.proj_player_fantasy_points fp
    on fp.player_id = dp.player_id and fp.projection_season = ? and fp.format_name = 'half_ppr'
left join analytics.proj_player_season_components pc
    on pc.player_id = dp.player_id and pc.projection_season = ?
left join analytics.superflex_mock_lean sml
    on sml.player_id = dp.player_id and sml.league_id = ?
left join staging.stg_durability_overrides ov
    on ov.player_id = dp.player_id and ov.has_gsis_match
where dp.player_id = ?
"""

ANALYST_RANKS_SQL = """
select analyst, normalized_position_rank as position_rank, tier, overall_rank
from staging.stg_analysts__draft_rankings
where player_id = ? and has_gsis_match
order by analyst
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
    parser.add_argument(
        "--my-slot",
        type=int,
        default=None,
        help="draft_slot to label 'You' (Sleeper mock drafts expose no real team names)",
    )
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


def style_remaining_by_position(row):
    # Same red/yellow/green intent as style_remaining, but thresholds scaled to
    # each position's own target instead of the whole-team $250 budget — a $27
    # TE target being "nearly tapped out" looks nothing like a $250 team budget
    # being nearly tapped out.
    target = row["target"]
    remaining = row["remaining"]
    if target <= 0:
        color = "#bad761"
    elif remaining < 0:
        color = "#ff657a"
    elif remaining < 0.3 * target:
        color = "#ffd76d"
    else:
        color = "#bad761"
    return [""] * len(row.index[:-1]) + [f"color: {color}"]


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
        budget_df = con.execute(BUDGET_SQL, [args.my_slot, args.budget]).fetch_df()
        target_df = con.execute(TARGET_BY_POSITION_SQL, [args.budget]).fetch_df()
        spent_df = con.execute(MY_SPEND_BY_POSITION_SQL, [args.my_slot]).fetch_df()
        board_df = con.execute(BOARD_SQL, [args.league_id, args.season]).fetch_df()
        market_pool_df = con.execute(
            "select reason, coalesce(sum(estimated_price), 0) as total "
            "from analytics.market_priced_player_values group by reason"
        ).fetch_df()
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
        rookie_pool_total = int(
            market_pool_df.loc[market_pool_df["reason"] == "rookie", "total"].sum()
        )
        situation_pool_total = int(
            market_pool_df.loc[market_pool_df["reason"] == "situation_change", "total"].sum()
        )
        market_pool_total = rookie_pool_total + situation_pool_total
        st.caption(
            f"Market-priced pool: ${market_pool_total} total (🆕 rookies ${rookie_pool_total} + "
            f"🔄 situation changes ${situation_pool_total}) — ~${market_pool_total / 12:.0f}/team "
            "if spread evenly across 12 teams. These prices are NOT part of the veteran price "
            "ceilings' $3,000 budget-conservation total (priced independently — see "
            "dbt/models/analytics/market_priced_player_values.sql), so this money still comes "
            "out of your real $250. Reserve accordingly before treating veteran price ceilings "
            "as literal."
        )

    with col2:
        st.subheader("Your budget by position")
        chart_df = (
            target_df.merge(spent_df, on="position", how="left")
            .fillna({"spent": 0})
        )
        missing_positions = set(spent_df["position"]) - set(target_df["position"])
        if missing_positions:
            extra = pd.DataFrame(
                {"position": list(missing_positions), "target": 0}
            ).merge(spent_df, on="position")
            chart_df = pd.concat([chart_df, extra], ignore_index=True)
        chart_df["remaining"] = chart_df["target"] - chart_df["spent"]
        chart_df = chart_df.sort_values("target", ascending=False).set_index("position")
        st.dataframe(
            chart_df[["target", "spent", "remaining"]].style.apply(
                style_remaining_by_position, axis=1
            ),
            width="stretch",
            column_config={
                "target": st.column_config.NumberColumn("target", format="$%.0f"),
                "spent": st.column_config.NumberColumn("spent", format="$%.0f"),
                "remaining": st.column_config.NumberColumn("remaining", format="$%.0f"),
            },
        )
        st.caption(
            "target = your share of the model's demand-weighted price-ceiling pool "
            "(player_auction_prices.sql), not a hard cap — spend over target where the "
            "board dictates."
        )

    st.subheader("Best remaining players (undrafted)")
    board_positions = st.pills(
        "Position", options=["QB", "RB", "WR", "TE"], selection_mode="multi",
        default=["QB", "RB", "WR", "TE"], key="board_position_filter",
    )
    if board_positions:
        board_df = board_df[board_df["position"].isin(board_positions)]
    market_priced_emoji = {"rookie": " 🆕", "situation_change": " 🔄"}
    board_df["player"] = board_df["player"] + board_df["market_priced_reason"].map(
        lambda r: market_priced_emoji.get(r, "")
    )
    st.dataframe(
        board_df.drop(columns=["market_priced_reason"]).style.map(style_lean, subset=["mock_lean"]),
        width="stretch",
        hide_index=True,
        height=650,
        column_config={
            "price": st.column_config.NumberColumn("price ceiling", format="$%d"),
            "vorp": st.column_config.NumberColumn("vorp", format="%.1f"),
            "mock_pick_no": st.column_config.NumberColumn(
                "mock pick",
                help="This player's pick number in a real 12-team superflex mock draft (12 "
                "different drafters) -- blank if this mock didn't draft them (or, for "
                "rookies, isn't covered at all).",
            ),
            "mock_lean": st.column_config.NumberColumn(
                "mock lean",
                help="Our VORP-based position rank minus the mock's pick-order position "
                "rank. Positive = the mock's drafters valued this player higher than our "
                "model does.",
            ),
            "heath_tier": st.column_config.NumberColumn(
                "Heath tier",
                help="Heath Cummings' (CBS) tier for this player, from his QB/RB/WR/TE "
                "tiers articles -- lower is better. His raw tier only, not blended with "
                "any other analyst or with our own VORP. Blank = he doesn't rank this "
                "player (K/DST, or outside his covered pool).",
            ),
            "price_adjusted": st.column_config.NumberColumn(
                "price adjustment",
                format="$%d",
                help="price ceiling + mock lean, floored at $1. A rough, mechanical nudge "
                "toward what the mock's room actually paid attention to -- not a re-fit "
                "price, just the ceiling shifted by the lean points. Blank mock lean is "
                "treated as 0 (no adjustment), including for all rookies (no mock lean at "
                "all in that union).",
            ),
        },
    )

    st.caption(
        "Price ceiling: $250-budget auction model — QB keeps the original hand-anchored "
        "gamma (no superflex market data to fit against); RB/WR/TE is fit against real CBS "
        "Consensus auction $ (moderate fit, r²≈0.33 — a calibrated estimate, not a verified "
        "one). Only ~90 players clear replacement level and get priced; everyone else is an "
        "implied $1 fill. Mock lean/pick: all positions, sourced from a real 12-team "
        "superflex mock draft's full pick order (revealed-preference demand) -- see "
        "dbt/models/analytics/superflex_mock_lean.sql. "
        "🆕 = rookie, no NFL season history for VORP to build from. 🔄 = situation change — "
        "present in our history but their trailing team no longer matches their current roster "
        "(trade/free agency/cut+sign): their own-history opportunity reflects a role they've "
        "left, and a tested team-volume correction didn't hold up, so it's repriced the same "
        "way as rookies. Both priced from real CBS auction $ and/or your analysts' rank "
        "(not VORP), and not part of the veteran $3,000 budget-conservation total — see "
        "dbt/models/analytics/market_priced_player_values.sql."
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
            [args.league_id, args.season, args.season, args.season, args.league_id, player_id],
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
        m5.metric("Heath tier", int(row.heath_tier) if pd.notna(row.heath_tier) else "—")

        if pd.notna(row.heath_tier):
            tier = int(row.heath_tier)
            if tier <= 2:
                st.success(
                    f"🟢 Heath tier {tier} — one of his top players at the position. "
                    "Worth extending your budget for."
                )
            elif tier <= 4:
                st.warning(
                    f"🟡 Heath tier {tier} — solid, but not a tier he'd stretch for. "
                    "Pay up to your price ceiling, don't chase."
                )
            else:
                st.error(
                    f"🔴 Heath tier {tier} — he sees this as a replaceable-tier player. "
                    "Don't overpay."
                )
        else:
            st.caption("Heath Cummings doesn't rank this player.")

        if pd.notna(row.superflex_mock_pick):
            flagged = " ⚠️" if row.superflex_mock_flagged else ""
            lean_note = (
                f"lean {row.superflex_mock_lean:+.0f} (our position rank {int(row.position_rank)} "
                f"vs. mock position rank {int(row.superflex_mock_position_rank)}; positive = the "
                "mock's drafters valued this player higher than our model does)"
            )
            st.caption(
                f"Superflex mock draft capital: pick {int(row.superflex_mock_pick)}{flagged} — "
                f"{lean_note}. From a single real 12-team superflex mock (12 different "
                "drafters) — genuine revealed-preference demand, not a stated ranking."
                + (" This pick has flagged extraction uncertainty — see the seed's notes." if row.superflex_mock_flagged else "")
            )

        proj_points = f"{row.proj_fantasy_points:.1f}" if pd.notna(row.proj_fantasy_points) else "—"
        st.markdown(f"**Projected 2026 fantasy points (half-PPR):** {proj_points}")
        if pd.notna(row.projected_games):
            if pd.notna(row.durability_override_games):
                st.caption(
                    f"Projected games: {row.projected_games:.1f} — ⚠️ manually overridden "
                    f"(model's fitted estimate replaced by human judgment). {row.durability_override_reason}"
                )
            else:
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
