{#
    normalize_player_name(name)

    Name-matching key for joining free-text analyst names (e.g. CBS byline articles) to
    dim_players.display_name. Strips periods/apostrophes and one trailing generational
    suffix (Jr./Sr./II/III/IV), lowercased. Applied to BOTH sides of a join -- sources
    disagree on which side keeps the suffix (Eisenberg drops "Jr." from Chris Godwin;
    dim_players keeps it), so stripping only one side still misses matches.

    This does NOT fix true nickname/spelling aliases (e.g. "Chigoziem Okonkwo" vs the
    roster's "Chig Okonkwo") -- those go in the analyst_name_aliases seed instead.
#}
{% macro normalize_player_name(name) %}
    trim(
        regexp_replace(
            regexp_replace(lower({{ name }}), '[.'']', '', 'g'),
            '\s+(jr|sr|ii|iii|iv|v)\.?$', '', 'g'
        )
    )
{% endmacro %}
