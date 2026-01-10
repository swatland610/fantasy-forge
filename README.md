# Fantasy Forge

A data engineering learning project for fantasy football analytics, built with modern data stack tooling.

## Tech Stack

- **Dagster** — Orchestration and asset management
- **dbt** — SQL transformations (project: `fantasy_forge`)
- **DuckDB** — Analytical database
- **nflreadpy** — NFL data ingestion

## Current Status

**Phase 0 complete**: Staging and core dbt layers with dimensional models (`dim_games`, `dim_players`, `dim_teams`, `fct_player_game_stats`), 31 passing tests, and 26 seasons of NFL data (1999-2025).

## Quick Start

```bash
# Install dependencies (requires uv)
uv sync
source .venv/bin/activate

# Initialize database
python scripts/init_db.py

# Start Dagster UI
dagster dev

# Run dbt models
cd dbt && dbt run && dbt test
```

## Project Structure

```
ff-data-platform/
├── ff_platform/       # Dagster definitions and assets
├── dbt/               # dbt models (staging → core → analytics)
├── data/              # DuckDB database and caches
├── notebooks/         # Exploration notebooks
└── scripts/           # Utility scripts
```

## Data Attribution

Data provided by [nflverse](https://github.com/nflverse/nflverse-data) under the MIT License.

Thanks to the nflverse team for compiling and maintaining comprehensive NFL statistics.

## License

MIT
