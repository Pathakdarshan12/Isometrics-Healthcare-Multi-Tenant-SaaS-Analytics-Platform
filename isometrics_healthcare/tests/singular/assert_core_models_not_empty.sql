-- Fails when the core tenant data is empty for the role running the build.
--
-- Every other test passes vacuously on empty tables, so a build that silently reads
-- zero rows (e.g. a row access policy on the raw tables rejecting the build role:
-- CI reads ISOMETRICS_DEV raw, and inside a policy CURRENT_DATABASE() is the
-- protected object's database) would otherwise go green.
-- Returns one row per empty model. Expected: zero rows.

with counts as (
    select 'stg_healthcare__encounters' as model_name, count(*) as row_count
    from {{ ref('stg_healthcare__encounters') }}
    union all
    select 'stg_healthcare__patients', count(*)
    from {{ ref('stg_healthcare__patients') }}
    union all
    select 'fct_encounters', count(*)
    from {{ ref('fct_encounters') }}
)

select model_name, row_count, 'Model is empty for the current role' as error_message
from counts
where row_count = 0
