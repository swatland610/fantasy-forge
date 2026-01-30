with source as (
    select * from {{ source('nflverse', 'injuries') }}
),

renamed as (
    select
        -- ===== IDENTIFIERS =====
        gsis_id,
        season,
        week,

        -- ===== PLAYER & TEAM =====
        full_name,
        position,
        team,

        -- ===== INJURY DETAILS =====
        report_primary_injury,
        report_secondary_injury,
        report_status,
        practice_primary_injury,
        practice_secondary_injury,
        practice_status,

        -- ===== METADATA =====
        date_modified,

        -- ===== DERIVED FIELDS =====
        true as is_on_injury_report,
        report_status in ('Out', 'Doubtful') as is_expected_out

    from source
    where 1 = 1
)

select * from renamed
