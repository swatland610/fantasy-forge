"""Dagster definitions entry point."""

from dagster import Definitions, define_asset_job, in_process_executor, load_assets_from_modules
from dagster_dbt import DbtCliResource

from ff_platform.assets import dbt_assets, nfl_data
from ff_platform.resources import DuckDBResource
from ff_platform.resources.dbt_project import dbt_project

all_assets = load_assets_from_modules([dbt_assets, nfl_data])

# Job for materializing all assets - uses in-process executor to avoid
# DuckDB lock conflicts (DuckDB only allows one write connection at a time)
materialize_all = define_asset_job(
    name="materialize_all",
    selection="*",
    executor_def=in_process_executor,
)

defs = Definitions(
    assets=all_assets,
    jobs=[materialize_all],
    resources={
        "duckdb": DuckDBResource(db_path="data/ff_platform.duckdb"),
        "dbt": DbtCliResource(project_dir=dbt_project),
    },
    # Default executor for ad-hoc materializations
    executor=in_process_executor,
)
