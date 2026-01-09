"""
Initialize the DuckDB database with schemas for the data warehouse.

This script creates the three-layer architecture:
- raw: Staging/raw NFL data from nflreadpy
- core: Cleaned and transformed data models (dbt)
- analytics: ML features and aggregations
"""

from pathlib import Path

import duckdb


def init_database(db_path: str = "data/ff_platform.duckdb"):
    """Initialize DuckDB database with warehouse schemas."""
    db_file = Path(db_path)
    db_file.parent.mkdir(parents=True, exist_ok=True)

    print(f"Initializing database at: {db_path}")

    with duckdb.connect(db_path) as conn:
        # Create schemas
        conn.execute("CREATE SCHEMA IF NOT EXISTS raw")
        conn.execute("CREATE SCHEMA IF NOT EXISTS staging")
        conn.execute("CREATE SCHEMA IF NOT EXISTS core")
        conn.execute("CREATE SCHEMA IF NOT EXISTS analytics")

        # Verify schemas were created
        schemas = conn.execute("""
            SELECT schema_name
            FROM information_schema.schemata
            WHERE schema_name IN ('raw', 'staging', 'core', 'analytics')
            ORDER BY schema_name
        """).fetchall()

        print("\nCreated schemas:")
        for schema in schemas:
            print(f"  ✓ {schema[0]}")

        # Show database info
        db_size = db_file.stat().st_size if db_file.exists() else 0
        print("\nDatabase initialized successfully!")
        print(f"Location: {db_file.absolute()}")
        print(f"Size: {db_size:,} bytes")


if __name__ == "__main__":
    init_database()
