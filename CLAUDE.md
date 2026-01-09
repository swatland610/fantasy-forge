# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Fantasy football data platform built on:
- **Dagster**: Orchestration and asset management
- **dbt**: SQL-based data transformations (project name: `fantasy_forge`)
- **DuckDB**: Analytical database/warehouse
- **nflreadpy**: NFL data ingestion
- **Polars/Pandas**: Data processing

## Development Commands

### Environment Setup
```bash
# Using uv package manager (Python 3.12-3.13)
uv sync                    # Install dependencies
source .venv/bin/activate  # Activate virtual environment
```

### Running the Project
```bash
# Start Dagster UI
dagster dev

# Run specific Dagster assets
dagster asset materialize --select <asset_name>

# Run dbt (from dbt/ directory)
cd dbt && dbt run
cd dbt && dbt test
```

### Development Workflow
```bash
# Initialize database (first time only)
python scripts/init_db.py

# Jupyter for exploration
jupyter notebook notebooks/explore.ipynb

# Run main entry point
python main.py

# Manual backup (optional, before major changes)
cp data/ff_platform.duckdb data/backups/ff_platform_$(date +%Y%m%d).duckdb
```

## Architecture

**Current State**: Core infrastructure in place with Dagster definitions, dbt models (staging layer), and populated DuckDB.

**Data Flow**:
```
nflreadpy (NFL raw data)
    ↓
Dagster assets (ff_platform/assets/)
    ↓
DuckDB raw schema
    ↓
dbt staging models (dbt/models/staging/)
    ↓
dbt core/analytics models
```

**Directory Structure**:
```
ff-data-platform/
├── data/
│   ├── ff_platform.duckdb      # Single DuckDB with multiple schemas
│   ├── backups/                # Manual backups
│   └── nflreadpy_cache/        # Cached NFL data from nflreadpy
├── dbt/                        # dbt project (fantasy_forge)
│   ├── models/
│   │   ├── staging/            # Staging models (stg_nflverse__*)
│   │   ├── core/               # Core transformed models
│   │   ├── analytics/          # ML features and aggregations
│   │   └── sources/            # Source definitions
│   ├── dbt_project.yml
│   └── profiles.yml
├── ff_platform/                # Dagster definitions module
│   ├── assets/                 # Dagster assets (nfl_data.py)
│   ├── resources/              # Dagster resources (duckdb.py)
│   └── definitions.py          # Main Dagster definitions
├── scripts/
│   └── init_db.py              # Initialize database schemas
├── notebooks/
│   └── explore.ipynb           # Data exploration notebook
├── logs/                       # Application logs
├── .env                        # Environment variables (not committed)
└── .env.example                # Environment template
```

**Database Schema Architecture**:
- **Single DuckDB file**: `data/ff_platform.duckdb`
- **Schemas**:
  - `raw`: Raw NFL data from nflreadpy (via Dagster assets)
  - `staging`: Cleaned staging models (dbt views)
  - `core`: Transformed models (dbt tables)
  - `analytics`: ML features and final aggregations (dbt tables)

## Key Patterns

- **Dagster Assets**: Software-defined assets in `ff_platform/assets/` represent data tables
- **dbt Models**: SQL transformations in `dbt/models/` organized by staging → core → analytics
- **DuckDB**: Single-file database for local development
- **Data Sources**: nflreadpy provides play-by-play, rosters, player stats, etc.

## Technology-Specific Notes

### Dagster
- Definitions in `ff_platform/definitions.py`
- Assets load NFL data via nflreadpy and persist to DuckDB
- Entry point configured in `pyproject.toml`: `ff_platform.definitions:defs`

### dbt
- DuckDB adapter: `dbt-duckdb`
- Profile: `fantasy_forge` (configured in `dbt/profiles.yml`)
- Staging models use `stg_nflverse__` prefix

### DuckDB
- Supports direct Parquet/CSV reads for incremental ingestion
- Use COPY for bulk loading from nflreadpy DataFrames

### nflreadpy
- Primary data source for NFL statistics
- Returns pandas DataFrames by default
- Cache stored in `data/nflreadpy_cache/`
