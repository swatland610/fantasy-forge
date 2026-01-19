
  {{
      config(
          materialized='table'
      )
  }}

  with player_game_stats as (
      select *
      from {{ ref('fct_player_game_stats') }}
      where position in ('WR', 'RB', 'TE')
        and offense_pct > 0
  ),

  -- Top N config per position
  position_limits (position, top_n) as (
      values
          ('WR', 3),
          ('RB', 2),
          ('TE', 2)
  ),

  -- Rank players within each game/team/position by snap %
  ranked_players as (
      select
          pgs.*,
          pl.top_n,
          row_number() over (
              partition by pgs.game_id, pgs.team, pgs.position
              order by pgs.offense_pct desc
          ) as position_rank
      from player_game_stats pgs
      inner join position_limits pl
          on pgs.position = pl.position
  ),

  -- Keep only top N per position per game
  top_players as (
      select *
      from ranked_players
      where position_rank <= top_n
  ),

  -- Aggregate thresholds by season and position
  final as (
      select
          season,
          position,
          count(*) as sample_size,

          -- Central tendency
          round(avg(offense_pct),2) as mean_offense_pct,
          round(percentile_cont(0.50) within group (order by offense_pct),2) as median_offense_pct,

          -- Quartiles
          round(percentile_cont(0.25) within group (order by offense_pct),2) as p25_offense_pct,
          round(percentile_cont(0.75) within group (order by offense_pct), 2)as p75_offense_pct,

          -- Spread
          round(stddev(offense_pct),2) as std_offense_pct,
          round(variance(offense_pct),2) as var_offense_pct,
          round(min(offense_pct),2) as min_offense_pct,
          round(max(offense_pct),2) as max_offense_pct

      from top_players
      group by season, position
  )

  select * from final
  order by season, position