"""DuckDB resource for Dagster."""

from pathlib import Path

import duckdb
from dagster import ConfigurableResource, InitResourceContext


class DuckDBResource(ConfigurableResource):
    """Configurable DuckDB database resource."""

    db_path: str = "data/ff_platform.duckdb"

    def _get_connection(self) -> duckdb.DuckDBPyConnection:
        """Create a new DuckDB connection."""
        path = Path(self.db_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        return duckdb.connect(str(path))

    def execute(self, query: str) -> None:
        """Execute a query without returning results."""
        with self._get_connection() as conn:
            conn.execute(query)

    def query(self, query: str) -> duckdb.DuckDBPyRelation:
        """Execute a query and return results as a relation."""
        with self._get_connection() as conn:
            return conn.execute(query).fetchall()

    def load_df(self, df, schema: str, table: str) -> None:
        """Load a DataFrame into a table (full replace)."""
        with self._get_connection() as conn:
            conn.execute(f"CREATE SCHEMA IF NOT EXISTS {schema}")
            conn.execute(
                f"CREATE OR REPLACE TABLE {schema}.{table} AS SELECT * FROM df"
            )

    def load_df_partitioned(
        self, df, schema: str, table: str, partition_col: str, partition_value: str
    ) -> None:
        """Load a DataFrame into a table, replacing only the specified partition."""
        with self._get_connection() as conn:
            conn.execute(f"CREATE SCHEMA IF NOT EXISTS {schema}")
            # Create table if it doesn't exist
            conn.execute(
                f"CREATE TABLE IF NOT EXISTS {schema}.{table} AS SELECT * FROM df WHERE 1=0"
            )
            # Delete existing partition data
            conn.execute(
                f"DELETE FROM {schema}.{table} WHERE {partition_col} = '{partition_value}'"
            )
            # Insert new partition data
            conn.execute(f"INSERT INTO {schema}.{table} SELECT * FROM df")
