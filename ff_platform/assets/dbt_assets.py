from typing import Any

from dagster import AssetExecutionContext
from dagster_dbt import DagsterDbtTranslator, DbtCliResource, dbt_assets

from ff_platform.resources.dbt_project import dbt_project


class CustomDbtTranslator(DagsterDbtTranslator):
    def get_group_name(self, dbt_resource_props: dict[str, Any]) -> str | None:
        """Use dbt's native group config for Dagster asset groups."""
        return dbt_resource_props.get("group")


@dbt_assets(
    manifest=dbt_project.manifest_path,
    dagster_dbt_translator=CustomDbtTranslator(),
)
def dbt_models(context: AssetExecutionContext, dbt: DbtCliResource):
    yield from dbt.cli(["build"], context=context).stream()
