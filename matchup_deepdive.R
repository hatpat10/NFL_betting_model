# ============================================================================
# NFL MATCHUP DEEP DIVE - FIXED VERSION
# ============================================================================
# This version properly handles 2-letter team abbreviations (like LV for Raiders)
# and fixes the date formatting issue

library(tidyverse)
library(nflreadr)
library(nflfastR)

# ============================================================================
# CONFIGURATION
# ============================================================================

# Set the matchup teams - supports both 2 and 3 letter abbreviations
HOME_TEAM <- "ATL"   # Denver Broncos
AWAY_TEAM <- "IND"    # Las Vegas Raiders (2-letter abbreviation is valid)

# Current season and week
CURRENT_SEASON <- 2025
CURRENT_WEEK <- 10

# ============================================================================
# LOAD SCHEDULE DATA
# ============================================================================

cat("Loading schedule data...\n")
schedule <- load_schedules(CURRENT_SEASON) %>%
  filter(week == CURRENT_WEEK)

# Find the specific game - handle both 2 and 3 letter abbreviations
game_info <- schedule %>%
  filter(
    (home_team == HOME_TEAM & away_team == AWAY_TEAM) |
      (home_team == AWAY_TEAM & away_team == HOME_TEAM)  # In case teams are swapped
  )

if (nrow(game_info) == 0) {
  cat("❌ Game not found for", AWAY_TEAM, "@", HOME_TEAM, "in Week", CURRENT_WEEK, "\n")
  cat("Available games this week:\n")
  schedule %>% 
    select(away_team, home_team) %>%
    mutate(matchup = paste(away_team, "@", home_team)) %>%
    pull(matchup) %>%
    cat(sep = "\n")
} else {
  cat("✓ Game found:\n")
  cat("    ", game_info$away_team, "@", game_info$home_team, "\n")
  
  # Fixed date formatting - check if gameday exists and format properly
  if ("gameday" %in% names(game_info) && !is.na(game_info$gameday)) {
    # Convert to Date if it's not already
    game_date <- as.Date(game_info$gameday)
    cat("    ", format(game_date, "%A, %B %d, %Y"), "\n")
  } else if ("game_date" %in% names(game_info) && !is.na(game_info$game_date)) {
    # Alternative column name
    game_date <- as.Date(game_info$game_date)
    cat("    ", format(game_date, "%A, %B %d, %Y"), "\n")
  } else {
    cat("    Date information not available\n")
  }
  
  # Display spread if available
  if ("spread_line" %in% names(game_info) && !is.na(game_info$spread_line)) {
    cat("    Spread:", HOME_TEAM, game_info$spread_line, "\n")
  }
  
  # Display total if available  
  if ("total_line" %in% names(game_info) && !is.na(game_info$total_line)) {
    cat("    Total:", game_info$total_line, "\n")
  }
}

cat("\n")

# ============================================================================
# LOAD TEAM STATS FOR THE SEASON
# ============================================================================

cat("Loading team statistics...\n")

# Load play-by-play data for the season
pbp_data <- load_pbp(CURRENT_SEASON) %>%
  filter(season_type == "REG", !is.na(epa), !is.na(posteam))

# Calculate team offensive stats
team_offense <- pbp_data %>%
  group_by(posteam) %>%
  summarize(
    games = n_distinct(game_id),
    plays = n(),
    epa_per_play = mean(epa, na.rm = TRUE),
    success_rate = mean(success, na.rm = TRUE),
    explosive_rate = mean(yards_gained >= 20, na.rm = TRUE),
    yards_per_play = mean(yards_gained, na.rm = TRUE),
    pass_rate = mean(play_type == "pass", na.rm = TRUE),
    rush_epa = mean(epa[play_type == "run"], na.rm = TRUE),
    pass_epa = mean(epa[play_type == "pass"], na.rm = TRUE),
    third_down_conv = mean(first_down[down == 3], na.rm = TRUE),
    red_zone_td_rate = mean(touchdown[yardline_100 <= 20], na.rm = TRUE),
    .groups = 'drop'
  ) %>%
  rename(team = posteam)

# Calculate team defensive stats
team_defense <- pbp_data %>%
  group_by(defteam) %>%
  summarize(
    games = n_distinct(game_id),
    plays_faced = n(),
    epa_allowed = mean(epa, na.rm = TRUE),
    success_allowed = mean(success, na.rm = TRUE),
    explosive_allowed = mean(yards_gained >= 20, na.rm = TRUE),
    yards_allowed = mean(yards_gained, na.rm = TRUE),
    turnovers_forced = sum(interception == 1 | fumble_lost == 1, na.rm = TRUE) / n_distinct(game_id),
    third_down_stop = 1 - mean(first_down[down == 3], na.rm = TRUE),
    red_zone_td_allowed = mean(touchdown[yardline_100 <= 20], na.rm = TRUE),
    .groups = 'drop'
  ) %>%
  rename(team = defteam)

# ============================================================================
# LAST 3 GAMES FORM
# ============================================================================

cat("Calculating recent form (last 3 games)...\n")

# Get last 3 games for each team
recent_games <- pbp_data %>%
  filter(week >= CURRENT_WEEK - 3, week < CURRENT_WEEK)

# Recent offensive form
recent_offense <- recent_games %>%
  group_by(posteam) %>%
  summarize(
    l3_games = n_distinct(game_id),
    l3_epa = mean(epa, na.rm = TRUE),
    l3_success = mean(success, na.rm = TRUE),
    l3_explosive = mean(yards_gained >= 20, na.rm = TRUE),
    l3_yards = mean(yards_gained, na.rm = TRUE),
    .groups = 'drop'
  ) %>%
  rename(team = posteam)

# Recent defensive form
recent_defense <- recent_games %>%
  group_by(defteam) %>%
  summarize(
    l3_def_epa = mean(epa, na.rm = TRUE),
    l3_def_success = mean(success, na.rm = TRUE),
    l3_def_explosive = mean(yards_gained >= 20, na.rm = TRUE),
    l3_def_yards = mean(yards_gained, na.rm = TRUE),
    .groups = 'drop'
  ) %>%
  rename(team = defteam)

# ============================================================================
# CREATE MATCHUP COMPARISON
# ============================================================================

cat("\n", strrep("=", 60), "\n", sep = "")
cat("MATCHUP ANALYSIS:", AWAY_TEAM, "@", HOME_TEAM, "\n")
cat(strrep("=", 60), "\n\n")

# Get stats for both teams
away_stats_off <- team_offense %>% filter(team == AWAY_TEAM)
away_stats_def <- team_defense %>% filter(team == AWAY_TEAM)
home_stats_off <- team_offense %>% filter(team == HOME_TEAM)
home_stats_def <- team_defense %>% filter(team == HOME_TEAM)

# Recent form
away_recent_off <- recent_offense %>% filter(team == AWAY_TEAM)
away_recent_def <- recent_defense %>% filter(team == AWAY_TEAM)
home_recent_off <- recent_offense %>% filter(team == HOME_TEAM)
home_recent_def <- recent_defense %>% filter(team == HOME_TEAM)

# ============================================================================
# DISPLAY TEAM COMPARISONS
# ============================================================================

cat("SEASON AVERAGES\n")
cat(strrep("-", 40), "\n")

# Offensive comparison
cat("\nOFFENSE:\n")
cat(sprintf("%-20s %8s %8s\n", "Metric", AWAY_TEAM, HOME_TEAM))
cat(strrep("-", 40), "\n")

if (nrow(away_stats_off) > 0 && nrow(home_stats_off) > 0) {
  cat(sprintf("%-20s %8.3f %8.3f\n", "EPA/Play", 
              away_stats_off$epa_per_play, home_stats_off$epa_per_play))
  cat(sprintf("%-20s %8.1f%% %7.1f%%\n", "Success Rate", 
              away_stats_off$success_rate * 100, home_stats_off$success_rate * 100))
  cat(sprintf("%-20s %8.1f %8.1f\n", "Yards/Play", 
              away_stats_off$yards_per_play, home_stats_off$yards_per_play))
  cat(sprintf("%-20s %8.1f%% %7.1f%%\n", "Explosive Play %", 
              away_stats_off$explosive_rate * 100, home_stats_off$explosive_rate * 100))
  cat(sprintf("%-20s %8.1f%% %7.1f%%\n", "3rd Down Conv", 
              away_stats_off$third_down_conv * 100, home_stats_off$third_down_conv * 100))
  cat(sprintf("%-20s %8.1f%% %7.1f%%\n", "RZ TD Rate", 
              away_stats_off$red_zone_td_rate * 100, home_stats_off$red_zone_td_rate * 100))
}

# Defensive comparison
cat("\nDEFENSE (lower is better):\n")
cat(sprintf("%-20s %8s %8s\n", "Metric", AWAY_TEAM, HOME_TEAM))
cat(strrep("-", 40), "\n")

if (nrow(away_stats_def) > 0 && nrow(home_stats_def) > 0) {
  cat(sprintf("%-20s %8.3f %8.3f\n", "EPA Allowed", 
              away_stats_def$epa_allowed, home_stats_def$epa_allowed))
  cat(sprintf("%-20s %8.1f%% %7.1f%%\n", "Success Allowed", 
              away_stats_def$success_allowed * 100, home_stats_def$success_allowed * 100))
  cat(sprintf("%-20s %8.1f %8.1f\n", "Yards Allowed", 
              away_stats_def$yards_allowed, home_stats_def$yards_allowed))
  cat(sprintf("%-20s %8.1f%% %7.1f%%\n", "Explosive Allowed", 
              away_stats_def$explosive_allowed * 100, home_stats_def$explosive_allowed * 100))
  cat(sprintf("%-20s %8.1f %8.1f\n", "TO/Game", 
              away_stats_def$turnovers_forced, home_stats_def$turnovers_forced))
  cat(sprintf("%-20s %8.1f%% %7.1f%%\n", "3rd Down Stops", 
              away_stats_def$third_down_stop * 100, home_stats_def$third_down_stop * 100))
}

# ============================================================================
# RECENT FORM (LAST 3 GAMES)
# ============================================================================

cat("\n\nRECENT FORM (Last 3 Games)\n")
cat(strrep("-", 40), "\n")

if (nrow(away_recent_off) > 0 && nrow(home_recent_off) > 0) {
  cat(sprintf("%-20s %8s %8s\n", "Metric", AWAY_TEAM, HOME_TEAM))
  cat(strrep("-", 40), "\n")
  cat(sprintf("%-20s %8.3f %8.3f\n", "Off EPA/Play", 
              away_recent_off$l3_epa, home_recent_off$l3_epa))
  cat(sprintf("%-20s %8.1f%% %7.1f%%\n", "Off Success", 
              away_recent_off$l3_success * 100, home_recent_off$l3_success * 100))
}

if (nrow(away_recent_def) > 0 && nrow(home_recent_def) > 0) {
  cat(sprintf("%-20s %8.3f %8.3f\n", "Def EPA Allowed", 
              away_recent_def$l3_def_epa, home_recent_def$l3_def_epa))
  cat(sprintf("%-20s %8.1f%% %7.1f%%\n", "Def Success All", 
              away_recent_def$l3_def_success * 100, home_recent_def$l3_def_success * 100))
}

# ============================================================================
# KEY MATCHUP ADVANTAGES
# ============================================================================

cat("\n\nKEY MATCHUP INSIGHTS\n")
cat(strrep("-", 40), "\n")

if (nrow(away_stats_off) > 0 && nrow(home_stats_def) > 0) {
  # Away offense vs Home defense
  away_off_adv <- away_stats_off$epa_per_play - home_stats_def$epa_allowed
  cat(sprintf("%s Offense vs %s Defense: %+.3f EPA advantage\n", 
              AWAY_TEAM, HOME_TEAM, away_off_adv))
}

if (nrow(home_stats_off) > 0 && nrow(away_stats_def) > 0) {
  # Home offense vs Away defense  
  home_off_adv <- home_stats_off$epa_per_play - away_stats_def$epa_allowed
  cat(sprintf("%s Offense vs %s Defense: %+.3f EPA advantage\n", 
              HOME_TEAM, AWAY_TEAM, home_off_adv))
}

# ============================================================================
# SIMPLE PREDICTION
# ============================================================================

cat("\n\nSIMPLE PROJECTION\n")
cat(strrep("-", 40), "\n")

if (nrow(away_stats_off) > 0 && nrow(away_stats_def) > 0 && 
    nrow(home_stats_off) > 0 && nrow(home_stats_def) > 0) {
  
  # Basic prediction using EPA differentials
  away_power <- away_stats_off$epa_per_play - away_stats_def$epa_allowed
  home_power <- home_stats_off$epa_per_play - home_stats_def$epa_allowed
  
  # Home field advantage (typical is ~2.5 points)
  HOME_FIELD_ADVANTAGE <- 2.5
  
  # Convert EPA differential to points (roughly 3.5 points per 0.1 EPA)
  predicted_margin <- (away_power - home_power) * 35 - HOME_FIELD_ADVANTAGE
  
  # Estimate total (league average is ~45-47 points)
  LEAGUE_AVG_TOTAL <- 46
  offensive_factor <- (away_stats_off$epa_per_play + home_stats_off$epa_per_play) / 0.10
  defensive_factor <- (away_stats_def$epa_allowed + home_stats_def$epa_allowed) / 0.10
  predicted_total <- LEAGUE_AVG_TOTAL + (offensive_factor - defensive_factor) * 2
  
  cat(sprintf("Predicted Score: %s %.1f, %s %.1f\n",
              HOME_TEAM, (predicted_total / 2) - (predicted_margin / 2),
              AWAY_TEAM, (predicted_total / 2) + (predicted_margin / 2)))
  
  cat(sprintf("Predicted Spread: %s %.1f\n", HOME_TEAM, predicted_margin))
  cat(sprintf("Predicted Total: %.1f\n", predicted_total))
  
  # Win probability (using normal distribution with SD ~13.5)
  win_prob <- pnorm(-predicted_margin, mean = 0, sd = 13.5)
  cat(sprintf("\nWin Probability: %s %.1f%%, %s %.1f%%\n",
              HOME_TEAM, win_prob * 100,
              AWAY_TEAM, (1 - win_prob) * 100))
}

cat("\n", strrep("=", 60), "\n", sep = "")
cat("Note: This is a simple EPA-based projection.\n")
cat("For more accurate predictions, use the full model.\n")
cat(strrep("=", 60), "\n")