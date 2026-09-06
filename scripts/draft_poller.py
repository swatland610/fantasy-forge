"""Poll Sleeper's public draft-picks endpoint and mirror results into DuckDB.

Sleeper's REST API needs no auth for this endpoint, so this bypasses the
project's Sleeper MCP server (which doesn't expose draft picks) and hits
https://api.sleeper.app/v1/draft/{draft_id}/picks directly.

Opens and closes the DuckDB connection on each poll (rather than holding it
open) so the Streamlit app (scripts/streamlit_app.py) can read the same file
concurrently without a long-held write lock.

Usage (from the main checkout, where data/ff_platform.duckdb lives):
    python scripts/draft_poller.py
    python scripts/draft_poller.py --draft-id 1383897104379822080 --interval 5
"""

import argparse
import json
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

import duckdb

DEFAULT_DRAFT_ID = "1383897104379822080"  # Cool Place, 2026
SLEEPER_API = "https://api.sleeper.app/v1/draft/{draft_id}/picks"

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS main.drafted_picks (
    pick_no INTEGER PRIMARY KEY,
    round INTEGER,
    roster_id INTEGER,
    picked_by VARCHAR,
    sleeper_player_id VARCHAR,
    player_name VARCHAR,
    position VARCHAR,
    team VARCHAR,
    amount INTEGER,
    is_keeper BOOLEAN,
    updated_at TIMESTAMP
)
"""


def fetch_picks(draft_id: str) -> list[dict]:
    url = SLEEPER_API.format(draft_id=draft_id)
    with urllib.request.urlopen(url, timeout=10) as resp:
        return json.loads(resp.read())


def to_row(pick: dict, fetched_at: datetime) -> tuple:
    meta = pick.get("metadata") or {}
    amount = meta.get("amount")
    return (
        pick.get("pick_no"),
        pick.get("round"),
        pick.get("roster_id"),
        pick.get("picked_by"),
        pick.get("player_id"),
        f"{meta.get('first_name', '')} {meta.get('last_name', '')}".strip() or None,
        meta.get("position"),
        meta.get("team"),
        int(amount) if amount not in (None, "") else None,
        bool(pick.get("is_keeper")),
        fetched_at,
    )


def sync_once(db_path: str, draft_id: str) -> int:
    picks = fetch_picks(draft_id)
    fetched_at = datetime.now(timezone.utc)
    rows = [to_row(p, fetched_at) for p in picks]

    con = duckdb.connect(db_path)
    try:
        con.execute(CREATE_TABLE_SQL)
        con.execute("BEGIN TRANSACTION")
        con.execute("DELETE FROM main.drafted_picks")
        if rows:
            con.executemany(
                """
                INSERT INTO main.drafted_picks VALUES
                (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                rows,
            )
        con.execute("COMMIT")
    finally:
        con.close()
    return len(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--draft-id", default=DEFAULT_DRAFT_ID)
    parser.add_argument("--db-path", default="data/ff_platform.duckdb")
    parser.add_argument("--interval", type=float, default=5.0, help="seconds between polls")
    parser.add_argument("--once", action="store_true", help="sync a single time and exit")
    args = parser.parse_args()

    if args.once:
        n = sync_once(args.db_path, args.draft_id)
        print(f"synced {n} picks")
        return

    print(f"[draft_poller] polling draft {args.draft_id} every {args.interval}s -> {args.db_path}")
    print("[draft_poller] Ctrl+C to stop")

    while True:
        ts = datetime.now().strftime("%H:%M:%S")
        try:
            n = sync_once(args.db_path, args.draft_id)
            print(f"[{ts}] synced {n} picks")
        except urllib.error.URLError as e:
            print(f"[{ts}] fetch failed ({e}), retrying next interval")
        except KeyboardInterrupt:
            raise
        except Exception as e:
            print(f"[{ts}] unexpected error: {e}, retrying next interval")

        try:
            time.sleep(args.interval)
        except KeyboardInterrupt:
            break

    print("[draft_poller] stopped")


if __name__ == "__main__":
    main()
