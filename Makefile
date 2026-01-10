.PHONY: db dev help

help: 
	@echo "db  - Open DuckDB UI in read-only mode"
	@echo "dev - Start Dagster's UI"

db: 
	duckdb -readonly -ui data/ff_platform.duckdb

dev: 
	dagster dev

