# ============================================================================
# EXPORT YOUR OG_PIPELINE FEATURES TO PYTHON FORMAT
# ============================================================================
# Purpose: Convert YOUR rich og_pipeline.R outputs to Python-compatible format
# Input: offense_weekly.csv and defense_weekly.csv (from og_pipeline.R)
# Output: Python-ready parquet files
# ============================================================================

library(tidyverse)
library(arrow)
library(nflreadr)

# ============================================================================
# CONFIGURATION - Update these paths if needed
# ============================================================================

BASE_DIR <- 'C:/Users/Patsc/Documents/nfl_betting_model'
setwd(BASE_DIR)

# Your og_pipeline.R outputs to these folders:
OG_PIPELINE_OUTPUT <- 'C:/Users/Patsc/Documents/nfl/week9'  # Adjust if different

# Python expects data in these locations:
PYTHON_DATA_DIR <- 'data'

cat("\n═══════════════════════════════════════════\n")
cat("  EXPORTING YOUR OG_PIPELINE FEATURES\n")
cat("═══════════════════════════════════════════\n\n")

# ============================================================================
# STEP 1: Load YOUR og_pipeline.R outputs
# ============================================================================

cat("[1/4] Loading YOUR offense/defense outputs from og_pipeline.R...\n")

# Check if files exist
offense_file <- file.path(OG_PIPELINE_OUTPUT, 'offense_weekly.csv')
defense_file <- file.path(OG_PIPELINE_OUTPUT, 'defense_weekly.csv')

if (!file.exists(offense_file)) {
  cat("\n❌ ERROR: offense_weekly.csv not found!\n")
  cat("Expected location:", offense_file, "\n")
  cat("\nPlease run og_pipeline.R first, or update OG_PIPELINE_OUTPUT path\n\n")
  stop("Missing offense_weekly.csv")
}

if (!file.exists(defense_file)) {
  cat("\n❌ ERROR: defense_weekly.csv not found!\n")
  cat("Expected location:", defense_file, "\n")
  cat("\nPlease run og_pipeline.R first, or update OG_PIPELINE_OUTPUT path\n\n")
  stop("Missing defense_weekly.csv")
}

# Load your outputs
offense <- read_csv(offense_file, show_col_types = FALSE)
defense <- read_csv(defense_file, show_col_types = FALSE)

cat("   ✓ Loaded", nrow(offense), "offense observations\n")
cat("   ✓ Loaded", nrow(defense), "defense observations\n")

# ============================================================================
# STEP 2: Export Schedules (if not already done)
# ============================================================================

cat("\n[2/4] Exporting schedules...\n")

dir.create(file.path(PYTHON_DATA_DIR, 'raw'), showWarnings = FALSE, recursive = TRUE)
schedules_file <- file.path(PYTHON_DATA_DIR, 'raw', 'schedules.parquet')

if (!file.exists(schedules_file)) {
  schedules <- load_schedules(2015:2025) %>%
    filter(game_type == "REG")
  
  write_parquet(schedules, schedules_file)
  cat("   ✓ Wrote schedules.parquet\n")
} else {
  cat("   ✓ schedules.parquet already exists\n")
}

# ============================================================================
# STEP 3: Combine YOUR offense + defense into team_week format
# ============================================================================

cat("\n[3/4] Combining YOUR features into Python-compatible format...\n")

# Your og_pipeline.R has RICH features - let's use them all!
team_week <- offense %>%
  # Your offense features
  select(
    season, week, team = offense_team,
    
    # Core EPA metrics (YOUR columns - adjust names if different)
    off_epa = avg_epa_per_play,
    off_sr = success_rate,
    off_epa_pass = avg_epa_pass,
    off_epa_rush = avg_epa_run,
    
    # Rolling windows (YOUR columns)
    off_epa_l3 = roll3_epa,
    off_epa_l5 = roll5_epa, 
    off_epa_l10 = roll10_epa,
    off_sr_l3 = roll3_sr,
    off_sr_l5 = roll5_sr,
    off_sr_l10 = roll10_sr,
    
    # Situational stats (YOUR rich features!)
    off_explosive = explosive_play_rate,
    off_third_down = third_down_rate,
    off_red_zone = red_zone_td_rate,
    
    # Pace
    plays = plays_per_game,
    pace_sec_per_play = seconds_per_play,
    
    # Keep everything else too
    everything()
  ) %>%
  # Join YOUR defense features
  left_join(
    defense %>%
      select(
        season, week, team = defense_team,
        def_epa = def_avg_epa_per_play,
        def_sr = def_success_rate_allowed,
        def_epa_pass = def_avg_epa_pass,
        def_epa_rush = def_avg_epa_run,
        def_explosive = def_explosive_play_rate_allowed,
        def_third_down = def_third_down_rate,
        def_red_zone = def_red_zone_td_rate_allowed,
        everything()
      ),
    by = c("season", "week", "team")
  ) %>%
  # Add last 6 games for Python compatibility
  group_by(team) %>%
  arrange(season, week) %>%
  mutate(
    off_epa_l6 = zoo::rollmean(off_epa, k = 6, fill = NA, align = "right"),
    off_sr_l6 = zoo::rollmean(off_sr, k = 6, fill = NA, align = "right"),
    def_epa_l6 = zoo::rollmean(def_epa, k = 6, fill = NA, align = "right"),
    def_sr_l6 = zoo::rollmean(def_sr, k = 6, fill = NA, align = "right")
  ) %>%
  ungroup()

# Export to Python format
dir.create(file.path(PYTHON_DATA_DIR, 'processed'), showWarnings = FALSE, recursive = TRUE)
write_parquet(team_week, file.path(PYTHON_DATA_DIR, 'processed', 'team_week.parquet'))

cat("   ✓ Exported", nrow(team_week), "team-week observations\n")
cat("   ✓ Features:", ncol(team_week) - 3, "(season/week/team excluded)\n")

# ============================================================================
# STEP 4: Create enhanced model table
# ============================================================================

cat("\n[4/4] Building enhanced model table with YOUR features...\n")

schedules <- read_parquet(schedules_file)

# Home team features
home_features <- team_week %>%
  rename_with(~paste0("home_", .), .cols = -c(season, week, team)) %>%
  rename(home_team = team)

# Away team features  
away_features <- team_week %>%
  rename_with(~paste0("away_", .), .cols = -c(season, week, team)) %>%
  rename(away_team = team)

# Join to schedules and create differentials
model_table <- schedules %>%
  left_join(home_features, by = c("season", "week", "home_team")) %>%
  left_join(away_features, by = c("season", "week", "away_team")) %>%
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
    
    # YOUR situational differentials
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
    
    # Labels for training
    margin = if_else(is.na(home_score) | is.na(away_score), 
                     NA_real_, 
                     home_score - away_score),
    total_points = if_else(is.na(home_score) | is.na(away_score),
                           NA_real_,
                           home_score + away_score),
    
    # Context flags (from YOUR data if available)
    ctx_home_field = 1,
    ctx_roof_dome = if_else(!is.na(roof) & roof == "dome", 1, 0),
    ctx_roof_outdoor = if_else(!is.na(roof) & roof == "outdoors", 1, 0),
    ctx_temp_cold = if_else(!is.na(temp) & temp < 40, 1, 0),
    ctx_temp_hot = if_else(!is.na(temp) & temp > 85, 1, 0),
    ctx_wind_high = if_else(!is.na(wind) & wind > 15, 1, 0)
  )

write_parquet(model_table, file.path(PYTHON_DATA_DIR, 'processed', 'model_table.parquet'))

cat("   ✓ Exported", nrow(model_table), "games to model_table.parquet\n")

# ============================================================================
# SUMMARY
# ============================================================================

cat("\n═══════════════════════════════════════════\n")
cat("  EXPORT COMPLETE!\n")
cat("═══════════════════════════════════════════\n\n")

feature_count <- sum(grepl("^delta_|^ctx_|^projected_pace", names(model_table)))

cat("📊 SUMMARY:\n")
cat("   Source: YOUR og_pipeline.R outputs\n")
cat("   Features exported:", feature_count, "\n")
cat("   Team-week observations:", nrow(team_week), "\n")
cat("   Games in model table:", nrow(model_table), "\n\n")

cat("💾 FILES CREATED:\n")
cat("   ✓", file.path(PYTHON_DATA_DIR, 'raw', 'schedules.parquet'), "\n")
cat("   ✓", file.path(PYTHON_DATA_DIR, 'processed', 'team_week.parquet'), "\n")
cat("   ✓", file.path(PYTHON_DATA_DIR, 'processed', 'model_table.parquet'), "\n\n")

cat("🎯 NEXT STEP:\n")
cat("   Run: python py/training/train_models_enhanced.py\n")
cat("   This will train ML using YOUR rich features!\n\n")

cat("✅ Your og_pipeline.R features are now Python-ready!\n\n")
