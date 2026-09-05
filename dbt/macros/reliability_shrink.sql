{#
    reliability_shrink(observed, baseline, n, k)

    Reliability-weighted shrinkage:  est = w*observed + (1-w)*baseline,  w = n/(n+k).
    See docs/reliability-weighted-shrinkage.md for the full derivation and the fitted k's.

    Three explicit fall-throughs to the baseline (the prior) -- none of these are silent
    NULL-coalescing; each is a documented branch of the model:
      * k IS NULL      -> we have no fitted reliability constant for this (position, component),
                          so we cannot weight the observation: fall back to the prior entirely.
      * n IS NULL / 0  -> the player had zero opportunities (the n->0 limit, w=0): pure prior.
      * observed NULL  -> the rate is undefined (0/0 upstream): there is nothing to blend in.
    In every other case we return the genuine blend.
#}
{% macro reliability_shrink(observed, baseline, n, k) %}
    case
        when {{ k }} is null               then {{ baseline }}
        when {{ n }} is null or {{ n }} = 0 then {{ baseline }}
        when {{ observed }} is null        then {{ baseline }}
        else ({{ n }} / ({{ n }} + {{ k }})) * {{ observed }}
           + ({{ k }} / ({{ n }} + {{ k }})) * {{ baseline }}
    end
{% endmacro %}
