# ============================================================================
# BRIDGE: Export R Features to Python-Compatible Format
# ============================================================================
# Purpose: Convert your rich R features to Parquet for Python ML training
# Run AFTER og_pipeline.R completes
# ============================================================================

library(tidyverse)
library(arrow)
library(nflreadr)

BASE_DIR <- 'C:/Users/Patsc/Documents/nfl'
WEEK_DIR <- file.path(BASE_DIR, 'week9')

# Python expects this structure:
PYTHON_DATA_DIR <- file.path(BASE_DIR, 'data')
dir.create(file.path(PYTHON_DATA_DIR, 'raw'), showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(PYTHON_DATA_DIR, 'processed'), showWarnings = FALSE, recursive = TRUE)

cat("\n═══════════════════════════════════════════\n")
cat("  EXPORTING R FEATURES → PYTHON FORMAT\n")
cat("═══════════════════════════════════════════\n\n")

# ============================================================================
# STEP 1: Export Schedules (Raw)
# ============================================================================

cat("[1/4] Exporting schedules...\n")

schedules <- load_schedules(2015:2025) %>%
  filter(game_type == "REG") %>%
  select(
    season, week, game_id, gameday,
    home_team, away_team,
    home_score, away_score,
    roof, surface, temp, wind,
    spread_line, total_line,
    home_coach, away_coach
  )

write_parquet(
  schedules,
  file.path(PYTHON_DATA_DIR, 'raw', 'schedules.parquet')
)

cat("   ✓ Wrote", nrow(schedules), "games\n")

# ============================================================================
# STEP 2: Export Team-Week Features (ALL Your Features!)
# ============================================================================

cat("[2/4] Exporting comprehensive team-week features...\n")

# Load your offense/defense files
offense <- read_csv(
  file.path(WEEK_DIR, 'offense_weekly.csv'),
  show_col_types = FALSE
)

defense <- read_csv(
  file.path(WEEK_DIR, 'defense_weekly.csv'),
  show_col_types = FALSE
)

# Combine offense + defense into single team-week table
team_week <- offense %>%
  left_join(
    defense %>%
      select(
        season, week, 
        team = defense_team,
        def_epa = def_avg_epa_per_play,
        def_sr = def_success_rate_allowed,
        def_epa_pass = def_avg_epa_pass,
        def_epa_rush = def_avg_epa_run,
        def_explosive = def_explosive_play_rate_allowed,
        def_third_down = def_third_down_rate,
        def_red_zone = def_red_zone_td_rate_allowed
      ),
    by = c("season", "week", "offense_team" = "team")
  ) %>%
  rename(team = offense_team) %>%
  select(
    season, week, team,
    
    # Offense features (your existing ones)
    off_epa = avg_epa_per_play,
    off_sr = success_rate,
    off_epa_pass = avg_epa_pass,
    off_epa_rush = avg_epa_run,
    off_explosive = explosive_play_rate,
    off_third_down = third_down_rate,
    off_red_zone = red_zone_td_rate,
    
    # Rolling windows (last 3, 5, 10 games)
    off_epa_l3 = roll3_epa,
    off_epa_l5 = roll5_epa,
    off_epa_l10 = roll10_epa,
    off_sr_l3 = roll3_sr,
    off_sr_l5 = roll5_sr,
    off_sr_l10 = roll10_sr,
    
    # Pace and plays
    plays = plays_per_game,
    pace_sec_per_play = seconds_per_play,
    
    # Defense features
    def_epa, def_sr,
    def_epa_pass, def_epa_rush,
    def_explosive, def_third_down, def_red_zone,
    
    # Context (if available in your files)
    everything()  # Keep any additional columns
  ) %>%
  # Add last 6 games (for compatibility with your Python code)
  group_by(team) %>%
  arrange(season, week) %>%
  mutate(
    off_epa_l6 = zoo::rollmean(off_epa, k = 6, fill = NA, align = "right"),
    off_sr_l6 = zoo::rollmean(off_sr, k = 6, fill = NA, align = "right"),
    def_epa_l6 = zoo::rollmean(def_epa, k = 6, fill = NA, align = "right"),
    def_sr_l6 = zoo::rollmean(def_sr, k = 6, fill = NA, align = "right")
  ) %>%
  ungroup()

write_parquet(
  team_week,
  file.path(PYTHON_DATA_DIR, 'processed', 'team_week.parquet')
)

cat("   ✓ Wrote", nrow(team_week), "team-week observations\n")
cat("   ✓ Features exported:", ncol(team_week) - 3, "(season/week/team excluded)\n")

# ============================================================================
# STEP 3: Create Enhanced Model Table (With ALL Features)
# ============================================================================

cat("[3/4] Building enhanced model table...\n")

# Create home/away features
home_features <- team_week %>%
  select(season, week, team, contains("off_"), contains("def_"), plays, pace_sec_per_play) %>%
  rename_with(~paste0("home_", .), .cols = -c(season, week, team)) %>%
  rename(home_team = team)

away_features <- team_week %>%
  select(season, week, team, contains("off_"), contains("def_"), plays, pace_sec_per_play) %>%
  rename_with(~paste0("away_", .), .cols = -c(season, week, team)) %>%
  rename(away_team = team)

# Join to schedules
model_table <- schedules %>%
  left_join(home_features, by = c("season", "week", "home_team")) %>%
  left_join(away_features, by = c("season", "week", "away_team")) %>%
  # Create differentials (home - away)
  mutate(
    # Core EPA differentials
    delta_off_epa = home_off_epa - away_off_epa,
    delta_def_epa = home_def_epa - away_def_epa,
    delta_off_sr = home_off_sr - away_off_sr,
    delta_def_sr = home_def_sr - away_def_sr,
    
    # Rolling window differentials
    delta_off_epa_l6 = home_off_epa_l6 - away_off_epa_l6,
    delta_off_sr_l6 = home_off_sr_l6 - away_off_sr_l6,
    delta_def_epa_l6 = home_def_epa_l6 - away_def_epa_l6,
    delta_def_sr_l6 = home_def_sr_l6 - away_def_sr_l6,
    
    # Situational differentials
    delta_off_third_down = home_off_third_down - away_off_third_down,
    delta_off_red_zone = home_off_red_zone - away_off_red_zone,
    delta_explosive = home_off_explosive - away_off_explosive,
    
    # Pass/Rush differentials
    delta_off_pass = home_off_epa_pass - away_off_epa_pass,
    delta_off_rush = home_off_epa_rush - away_off_epa_rush,
    delta_def_pass = home_def_epa_pass - away_def_epa_pass,
    delta_def_rush = home_def_epa_rush - away_def_epa_rush,
    
    # Pace
    projected_pace = (home_plays + away_plays) / 2,
    delta_pace = home_pace_sec_per_play - away_pace_sec_per_play,
    
    # Labels (for training)
    margin = if_else(is.na(home_score) | is.na(away_score), 
                     NA_real_, 
                     home_score - away_score),
    total_points = if_else(is.na(home_score) | is.na(away_score),
                           NA_real_,
                           home_score + away_score),
    
    # Context flags
    ctx_home_field = 1,
    ctx_roof_dome = if_else(roof == "dome", 1, 0),
    ctx_roof_outdoor = if_else(roof == "outdoors", 1, 0),
    ctx_temp_cold = if_else(!is.na(temp) & temp < 40, 1, 0),
    ctx_temp_hot = if_else(!is.na(temp) & temp > 85, 1, 0),
    ctx_wind_high = if_else(!is.na(wind) & wind > 15, 1, 0)
  )

write_parquet(
  model_table,
  file.path(PYTHON_DATA_DIR, 'processed', 'model_table.parquet')
)

cat("   ✓ Wrote", nrow(model_table), "game observations\n")

# ============================================================================
# STEP 4: Summary Report
# ============================================================================

cat("[4/4] Generating feature summary...\n\n")

feature_summary <- tibble(
  category = c(
    "Core EPA (Season)", "Core EPA (L6)", 
    "Defense (Season)", "Defense (L6)",
    "Situational", "Pass/Rush Splits",
    "Context", "Pace", "Labels"
  ),
  count = c(
    sum(grepl("delta_off_epa$|delta_off_sr$", names(model_table))),
    sum(grepl("delta_off_epa_l6|delta_off_sr_l6", names(model_table))),
    sum(grepl("delta_def_epa$|delta_def_sr$", names(model_table))),
    sum(grepl("delta_def_epa_l6|delta_def_sr_l6", names(model_table))),
    sum(grepl("delta_off_third|delta_off_red|delta_explosive", names(model_table))),
    sum(grepl("delta_off_pass|delta_off_rush|delta_def_pass|delta_def_rush", names(model_table))),
    sum(grepl("ctx_", names(model_table))),
    sum(grepl("pace", names(model_table))),
    sum(grepl("^margin$|^total_points$", names(model_table)))
  ),
  examples = c(
    "delta_off_epa, delta_off_sr",
    "delta_off_epa_l6, delta_off_sr_l6",
    "delta_def_epa, delta_def_sr",
    "delta_def_epa_l6, delta_def_sr_l6",
    "delta_off_third_down, delta_off_red_zone",
    "delta_off_pass, delta_def_rush",
    "ctx_home_field, ctx_roof_dome, ctx_temp_cold",
    "projected_pace, delta_pace",
    "margin, total_points"
  )
)

cat("═══════════════════════════════════════════\n")
cat("  FEATURE EXPORT SUMMARY\n")
cat("═══════════════════════════════════════════\n\n")

print(feature_summary, n = Inf)

cat("\n📊 COMPARISON:\n")
cat("   Your Python code currently uses: 5 features\n")
cat("   Now available: ", sum(grepl("^delta_|^ctx_|pace", names(model_table))), " features\n\n", sep = "")

cat("💾 FILES CREATED:\n")
cat("   ✓", file.path(PYTHON_DATA_DIR, 'raw', 'schedules.parquet'), "\n")
cat("   ✓", file.path(PYTHON_DATA_DIR, 'processed', 'team_week.parquet'), "\n")
cat("   ✓", file.path(PYTHON_DATA_DIR, 'processed', 'model_table.parquet'), "\n\n")

cat("🎯 NEXT STEP:\n")
cat("   Run the enhanced Python training script:\n")
cat("   python train_models_enhanced.py\n\n")
