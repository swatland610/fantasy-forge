# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Fantasy football data platform built on:
- **Dagster**: Orchestration and asset management
- **dbt**: SQL-based data transformations
- **DuckDB**: Analytical database/warehouse
- **nflreadpy**: NFL data ingestion
- **Polars/Pandas**: Data processing

## Development Commands

### Environment Setup
```bash
# Using uv package manager (Python 3.14+)
uv sync                    # Install dependencies
source .venv/bin/activate  # Activate virtual environment
```

### Running the Project
```bash
# Start Dagster UI
dagster dev

# Run specific Dagster assets (once defined)
dagster asset materialize --select <asset_name>

# Run dbt (once dbt project is set up)
dbt run
dbt test
```

### Development Workflow
```bash
# Initialize database (first time only)
python scripts/init_db.py

# Jupyter for exploration
jupyter notebook explore.ipynb

# Run main entry point
python main.py

# Manual backup (optional, before major changes)
cp data/ff_platform.duckdb data/backups/ff_platform_$(date +%Y%m%d).duckdb
```

## Architecture

**Current State**: Early-stage initialization - core dependencies installed but pipeline structure not yet built.

**Intended Data Flow**:
```
nflreadpy (NFL raw data)
    ↓
DuckDB (staging/raw storage)
    ↓
dbt models (transformations)
    ↓
DuckDB (analytics tables)
    ↓
Dagster assets (orchestration)
```

**Directory Structure**:
```
ff-data-platform/
├── data/
│   ├── ff_platform.duckdb      # Single DuckDB with 3 schemas
│   └── backups/                # Optional manual backups
├── scripts/
│   └── init_db.py              # Initialize database schemas
├── dagster_definitions/        # (To be created) Dagster assets, jobs
├── dbt_project/                # (To be created) dbt models, tests
└── notebooks/                  # (To be created) Analysis notebooks
```

**Database Schema Architecture**:
- **Single DuckDB file**: `data/ff_platform.duckdb`
- **Three logical schemas**:
  - `raw`: Staging/raw NFL data from nflreadpy
  - `core`: Cleaned and transformed models (dbt)
  - `analytics`: ML features and final aggregations

## Key Patterns

- **Dagster Assets**: Use software-defined assets to represent data tables/views
- **dbt Models**: SQL transformations organized by staging → intermediate → marts
- **DuckDB**: Single-file database for local development, partitioned tables for production
- **Data Sources**: nflreadpy provides play-by-play, rosters, draft picks, etc.

## Technology-Specific Notes

### Dagster
- Dagster integrates with dbt via `dagster-dbt` (add to dependencies when ready)
- Assets should map to dbt models for lineage tracking
- Use partitioned assets for time-series NFL data (by season/week)

### dbt
- DuckDB adapter: Use `duckdb-dbt` connector
- Models should separate raw NFL data from fantasy-specific metrics
- Leverage DuckDB's analytical functions for aggregations

### DuckDB
- Supports direct Parquet/CSV reads for incremental ingestion
- ATTACH/DETACH databases for multi-file setups
- Use COPY for bulk loading from nflreadpy DataFrames

### nflreadpy
- Primary data source for NFL statistics
- Returns pandas DataFrames by default
- Key functions: `load_pbp()`, `load_draft_picks()`, `load_rosters()`
