{#
    normalize_team_code(team)

    Maps a team abbreviation to nflverse's spelling for teams where analyst sources commonly
    differ (CBS/Sleeper use JAC/LAR; nflverse/dim_players use JAX/LA). Used for COMPARISON only
    (team_mismatch, join tiebreaks) -- raw values are still stored/exposed as-is so provenance
    isn't lost.
#}
{% macro normalize_team_code(team) %}
    case {{ team }}
        when 'LA' then 'LAR'
        when 'JAC' then 'JAX'
        when 'WSH' then 'WAS'
        else {{ team }}
    end
{% endmacro %}
