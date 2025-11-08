# ============================================================================
# BRIDGE: Export Features to Python (Works with og_pipeline OR 02_features)
# ============================================================================
# Purpose: Convert R features to Python-compatible Parquet format
# Detects which R script you ran and exports accordingly
# ============================================================================

library(tidyverse)
library(arrow)
library(nflreadr)

BASE_DIR <- getwd()  # Current working directory
PYTHON_DATA_DIR <- file.path(BASE_DIR, 'data')

cat("\n═══════════════════════════════════════════\n")
cat("  EXPORTING R FEATURES → PYTHON FORMAT\n")
cat("═══════════════════════════════════════════\n\n")

# Create directories
dir.create(file.path(PYTHON_DATA_DIR, 'raw'), showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(PYTHON_DATA_DIR, 'processed'), showWarnings = FALSE, recursive = TRUE)

# ============================================================================
# DETECT WHICH FEATURE FILES EXIST
# ============================================================================

cat("[1/5] Detecting available feature files...\n")

# Option 1: Your original og_pipeline outputs
og_offense_path <- file.path(BASE_DIR, 'week9', 'offense_weekly.csv')
og_defense_path <- file.path(BASE_DIR, 'week9', 'defense_weekly.csv')

# Option 2: In data/legacy (if copied)
legacy_offense_path <- file.path(PYTHON_DATA_DIR, 'legacy', 'offense_weekly.csv')
legacy_defense_path <- file.path(PYTHON_DATA_DIR, 'legacy', 'defense_weekly.csv')

# Option 3: ChatGPT's 02_features outputs (in R/data/)
chatgpt_team_week <- file.path(BASE_DIR, 'R', 'data', 'processed', 'team_week.parquet')

# Determine which to use
if (file.exists(og_offense_path) && file.exists(og_defense_path)) {
  cat("   ✓ Found og_pipeline outputs (BEST - 20+ features)\n")
  cat("     Using:", og_offense_path, "\n")
  USE_METHOD <- "og_pipeline"
  offense_source <- og_offense_path
  defense_source <- og_defense_path
} else if (file.exists(legacy_offense_path) && file.exists(legacy_defense_path)) {
  cat("   ✓ Found legacy files in data/ (20+ features)\n")
  USE_METHOD <- "og_pipeline"
  offense_source <- legacy_offense_path
  defense_source <- legacy_defense_path
} else if (file.exists(chatgpt_team_week)) {
  cat("   ✓ Found 02_features_team_week outputs (10-12 features)\n")
  cat("     Using:", chatgpt_team_week, "\n")
  USE_METHOD <- "chatgpt"
} else {
  stop("ERROR: No feature files found!\n",
       "Run one of these first:\n",
       "  - R/03_rich_features.R (og_pipeline), OR\n",
       "  - R/02_features_team_week.R (ChatGPT)")
}

# ============================================================================
# STEP 2: Export Schedules (Raw)
# ============================================================================

cat("\n[2/5] Exporting schedules...\n")

# Check if schedules already exist
sched_source <- file.path(BASE_DIR, 'R', 'data', 'raw', 'schedules.parquet')
if (!file.exists(sched_source)) {
  sched_source <- file.path(PYTHON_DATA_DIR, 'raw', 'schedules.parquet')
}

if (file.exists(sched_source)) {
  cat("   Schedules already exist, copying...\n")
  schedules <- read_parquet(sched_source)
} else {
  cat("   Downloading schedules from nflverse...\n")
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
}

write_parquet(
  schedules,
  file.path(PYTHON_DATA_DIR, 'raw', 'schedules.parquet')
)

cat("   ✓ Wrote", nrow(schedules), "games\n")

# ============================================================================
# STEP 3: Export Team-Week Features
# ============================================================================

cat("\n[3/5] Exporting team-week features...\n")

if (USE_METHOD == "og_pipeline") {
  
  # Load YOUR rich features
  offense <- read_csv(offense_source, show_col_types = FALSE)
  defense <- read_csv(defense_source, show_col_types = FALSE)
  
  # Combine offense + defense
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
      
      # Offense features
      off_epa = avg_epa_per_play,
      off_sr = success_rate,
      off_epa_pass = avg_epa_pass,
      off_epa_rush = avg_epa_run,
      off_explosive = explosive_play_rate,
      off_third_down = third_down_rate,
      off_red_zone = red_zone_td_rate,
      
      # Rolling windows
      off_epa_l3 = roll3_epa,
      off_epa_l5 = roll5_epa,
      off_epa_l10 = roll10_epa,
      off_sr_l3 = roll3_sr,
      off_sr_l5 = roll5_sr,
      off_sr_l10 = roll10_sr,
      
      # Pace
      plays = plays_per_game,
      pace_sec_per_play = seconds_per_play,
      
      # Defense
      def_epa, def_sr,
      def_epa_pass, def_epa_rush,
      def_explosive, def_third_down, def_red_zone,
      
      # Keep everything else
      everything()
    )
  
  # Add last 6 rolling (for compatibility)
  team_week <- team_week %>%
    group_by(team) %>%
    arrange(season, week) %>%
    mutate(
      off_epa_l6 = zoo::rollmean(off_epa, k = 6, fill = NA, align = "right"),
      off_sr_l6 = zoo::rollmean(off_sr, k = 6, fill = NA, align = "right"),
      def_epa_l6 = zoo::rollmean(def_epa, k = 6, fill = NA, align = "right"),
      def_sr_l6 = zoo::rollmean(def_sr, k = 6, fill = NA, align = "right")
    ) %>%
    ungroup()
  
  cat("   ✓ Using og_pipeline features (RICH)\n")
  
} else {
  # Load ChatGPT's basic features
  team_week <- read_parquet(chatgpt_team_week)
  
  cat("   ✓ Using 02_features outputs (BASIC)\n")
}

write_parquet(
  team_week,
  file.path(PYTHON_DATA_DIR, 'processed', 'team_week.parquet')
)

cat("   ✓ Wrote", nrow(team_week), "team-week observations\n")
cat("   ✓ Features exported:", ncol(team_week) - 3, "(excluding season/week/team)\n")

# ============================================================================
# STEP 4: Create Model Table (Home vs Away)
# ============================================================================

cat("\n[4/5] Building model table...\n")

# Create home/away features
home_features <- team_week %>%
  select(season, week, team, starts_with("off_"), starts_with("def_"), 
         plays, starts_with("pace")) %>%
  rename_with(~paste0("home_", .), .cols = -c(season, week, team)) %>%
  rename(home_team = team)

away_features <- team_week %>%
  select(season, week, team, starts_with("off_"), starts_with("def_"), 
         plays, starts_with("pace")) %>%
  rename_with(~paste0("away_", .), .cols = -c(season, week, team)) %>%
  rename(away_team = team)

# Join to schedules
model_table <- schedules %>%
  left_join(home_features, by = c("season", "week", "home_team")) %>%
  left_join(away_features, by = c("season", "week", "away_team")) %>%
  mutate(
    # Core EPA differentials
    delta_off_epa = home_off_epa - away_off_epa,
    delta_def_epa = home_def_epa - away_def_epa,
    delta_off_sr = home_off_sr - away_off_sr,
    delta_def_sr = home_def_sr - away_def_sr,
    
    # Rolling differentials (if available)
    delta_off_epa_l6 = if_else(
      !is.na(home_off_epa_l6), 
      home_off_epa_l6 - away_off_epa_l6, 
      NA_real_
    ),
    delta_off_sr_l6 = if_else(
      !is.na(home_off_sr_l6),
      home_off_sr_l6 - away_off_sr_l6,
      NA_real_
    ),
    delta_def_epa_l6 = if_else(
      !is.na(home_def_epa_l6),
      home_def_epa_l6 - away_def_epa_l6,
      NA_real_
    ),
    delta_def_sr_l6 = if_else(
      !is.na(home_def_sr_l6),
      home_def_sr_l6 - away_def_sr_l6,
      NA_real_
    ),
    
    # Situational differentials (if available)
    delta_off_third_down = if_else(
      !is.na(home_off_third_down),
      home_off_third_down - away_off_third_down,
      NA_real_
    ),
    delta_off_red_zone = if_else(
      !is.na(home_off_red_zone),
      home_off_red_zone - away_off_red_zone,
      NA_real_
    ),
    delta_explosive = if_else(
      !is.na(home_off_explosive),
      home_off_explosive - away_off_explosive,
      NA_real_
    ),
    
    # Pass/Rush differentials (if available)
    delta_off_pass = if_else(
      !is.na(home_off_epa_pass),
      home_off_epa_pass - away_off_epa_pass,
      NA_real_
    ),
    delta_off_rush = if_else(
      !is.na(home_off_epa_rush),
      home_off_epa_rush - away_off_epa_rush,
      NA_real_
    ),
    delta_def_pass = if_else(
      !is.na(home_def_epa_pass),
      home_def_epa_pass - away_def_epa_pass,
      NA_real_
    ),
    delta_def_rush = if_else(
      !is.na(home_def_epa_rush),
      home_def_epa_rush - away_def_epa_rush,
      NA_real_
    ),
    
    # Pace
    projected_pace = if_else(
      !is.na(home_plays),
      (home_plays + away_plays) / 2,
      NA_real_
    ),
    delta_pace = if_else(
      !is.na(home_pace_sec_per_play),
      home_pace_sec_per_play - away_pace_sec_per_play,
      NA_real_
    ),
    
    # Labels
    margin = if_else(
      is.na(home_score) | is.na(away_score), 
      NA_real_, 
      home_score - away_score
    ),
    total_points = if_else(
      is.na(home_score) | is.na(away_score),
      NA_real_,
      home_score + away_score
    ),
    
    # Context
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
# STEP 5: Summary Report
# ============================================================================

cat("\n[5/5] Summary...\n\n")

delta_cols <- names(model_table)[grepl("^delta_|^ctx_|^projected_pace", names(model_table))]
cat("═══════════════════════════════════════════\n")
cat("  FEATURE EXPORT COMPLETE\n")
cat("═══════════════════════════════════════════\n\n")

cat("Source:", USE_METHOD, "\n")
cat("Features exported:", length(delta_cols), "\n\n")

cat("Feature categories:\n")
cat("  - Core EPA:", sum(grepl("delta_off_epa$|delta_def_epa$", delta_cols)), "\n")
cat("  - Rolling (L6):", sum(grepl("_l6", delta_cols)), "\n")
cat("  - Situational:", sum(grepl("third|red|explosive", delta_cols)), "\n")
cat("  - Pass/Rush:", sum(grepl("pass|rush", delta_cols)), "\n")
cat("  - Context:", sum(grepl("ctx_", delta_cols)), "\n")
cat("  - Pace:", sum(grepl("pace", delta_cols)), "\n\n")

cat("💾 FILES CREATED:\n")
cat("   ✓", file.path(PYTHON_DATA_DIR, 'raw', 'schedules.parquet'), "\n")
cat("   ✓", file.path(PYTHON_DATA_DIR, 'processed', 'team_week.parquet'), "\n")
cat("   ✓", file.path(PYTHON_DATA_DIR, 'processed', 'model_table.parquet'), "\n\n")

cat("🎯 NEXT STEP:\n")
if (USE_METHOD == "og_pipeline") {
  cat("   ✅ Using RICH features from og_pipeline\n")
  cat("   Python will get 20+ features!\n")
} else {
  cat("   ⚠️  Using BASIC features from 02_features\n")
  cat("   For BETTER results:\n")
  cat("   1. Copy og_pipeline.R to R/ folder\n")
  cat("   2. Run it to generate rich features\n")
  cat("   3. Re-run this script\n")
}
cat("\n   Run: python py/training/train_models_enhanced.py\n\n")
