# ============================================================================
# NFL WEEKLY PREDICTION TRACKER
# ============================================================================
# Purpose: Track ALL predictions week-by-week with results and running record
# Shows: Game winner predictions, ATS predictions, actual results, records
# ============================================================================

rm(list = ls())
gc()

# ============================================================================
# CONFIGURATION
# ============================================================================

SEASON <- 2025
CURRENT_WEEK <- 7  # Most recent completed week
START_WEEK <- 1    # First week to analyze
BASE_DIR <- 'C:/Users/Patsc/Documents/nfl/R_files/test_output'

cat("\n")
cat("â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—\n")
cat("â•‘        NFL WEEKLY PREDICTION TRACKER                           â•‘\n")
cat("â•‘        Tracking Weeks", START_WEEK, "-", CURRENT_WEEK, "                                    â•‘\n")
cat("â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•\n")
cat("\n")

# ============================================================================
# LOAD PACKAGES
# ============================================================================

required_packages <- c(
  "nflverse", "nflreadr", "nflfastR", "dplyr", "tidyr", 
  "writexl", "ggplot2", "zoo", "scales"
)

for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
  suppressPackageStartupMessages(library(pkg, character.only = TRUE))
}

cat("âœ“ Packages loaded\n\n")

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

safe_mean <- function(x, na.rm = TRUE) {
  if (length(x) == 0 || all(is.na(x))) return(NA_real_)
  mean(x, na.rm = na.rm)
}

safe_sum <- function(x, na.rm = TRUE) {
  if (length(x) == 0) return(0)
  sum(x, na.rm = na.rm)
}

safe_rollmean <- function(x, k = 3, fill = NA, align = "right") {
  if (length(x) < 2) return(rep(NA_real_, length(x)))
  actual_k <- min(k, length(x))
  if (actual_k < 2) return(rep(NA_real_, length(x)))
  tryCatch({
    zoo::rollmean(x, k = actual_k, fill = fill, align = align)
  }, error = function(e) {
    rep(NA_real_, length(x))
  })
}

# ============================================================================
# LOAD ALL DATA
# ============================================================================

cat("Loading season data...\n")

# Load play-by-play
pbp_raw <- nflreadr::load_pbp(SEASON) %>%
  filter(
    season_type == "REG",
    week <= CURRENT_WEEK,
    !is.na(play_type),
    !is.na(down),
    play_type %in% c("pass", "run")
  )

# Load game results
schedule <- nflreadr::load_schedules(SEASON) %>%
  filter(
    game_type == "REG",
    week >= START_WEEK,
    week <= CURRENT_WEEK,
    !is.na(home_team),
    !is.na(away_team)
  ) %>%
  mutate(
    game_completed = !is.na(home_score) & !is.na(away_score),
    actual_home_score = if_else(game_completed, home_score, NA_real_),
    actual_away_score = if_else(game_completed, away_score, NA_real_),
    actual_margin = if_else(game_completed, home_score - away_score, NA_real_),
    actual_winner = case_when(
      !game_completed ~ NA_character_,
      home_score > away_score ~ home_team,
      away_score > home_score ~ away_team,
      TRUE ~ "TIE"
    ),
    home_covered_spread = case_when(
      !game_completed | is.na(spread_line) ~ NA,
      actual_margin > spread_line ~ TRUE,
      actual_margin < spread_line ~ FALSE,
      TRUE ~ NA  # Push
    )
  )

cat("âœ“ Loaded data for", n_distinct(schedule$week), "weeks and", nrow(schedule), "games\n\n")

# ============================================================================
# BUILD TEAM STATS FOR EACH WEEK
# ============================================================================

cat("Building team statistics week-by-week...\n")

# Aggregate team offense by week
team_offense_weekly <- pbp_raw %>%
  filter(!is.na(posteam), !is.na(epa)) %>%
  group_by(team_abbr = posteam, week) %>%
  summarise(
    plays = n(),
    avg_epa = safe_mean(epa),
    avg_epa_pass = safe_mean(epa[pass == 1]),
    avg_epa_run = safe_mean(epa[rush == 1]),
    success_rate = safe_mean(success),
    yards_per_play = safe_mean(yards_gained),
    .groups = "drop"
  )

# Calculate rolling averages
team_offense_rolling <- team_offense_weekly %>%
  arrange(team_abbr, week) %>%
  group_by(team_abbr) %>%
  mutate(
    roll3_epa = safe_rollmean(avg_epa, k = 3),
    season_avg_epa = cummean(avg_epa)  # Cumulative average up to each week
  ) %>%
  ungroup()

# Aggregate team defense by week
team_defense_weekly <- pbp_raw %>%
  filter(!is.na(defteam), !is.na(epa)) %>%
  group_by(team_abbr = defteam, week) %>%
  summarise(
    def_avg_epa = safe_mean(epa),
    def_success_rate = safe_mean(success),
    .groups = "drop"
  )

# Calculate rolling averages
team_defense_rolling <- team_defense_weekly %>%
  arrange(team_abbr, week) %>%
  group_by(team_abbr) %>%
  mutate(
    def_roll3_epa = safe_rollmean(def_avg_epa, k = 3),
    def_season_avg_epa = cummean(def_avg_epa)
  ) %>%
  ungroup()

cat("âœ“ Team statistics calculated\n\n")

# ============================================================================
# GENERATE PREDICTIONS FOR EACH WEEK
# ============================================================================

cat("Generating predictions for all weeks...\n")

all_week_predictions <- list()

for (pred_week in START_WEEK:CURRENT_WEEK) {
  cat("  Week", pred_week, "...\n")
  
  week_games <- schedule %>% filter(week == pred_week)
  
  if (nrow(week_games) == 0) next
  
  # Get stats available BEFORE this week (use data from week-1)
  if (pred_week == 1) {
    # Week 1: No prior data, use league averages
    home_off_epa <- 0
    away_off_epa <- 0
    home_def_epa <- 0
    away_def_epa <- 0
    
    # Create predictions for Week 1 with minimal info
    for (i in 1:nrow(week_games)) {
      game <- week_games[i, ]
      
      prediction <- tibble(
        week = pred_week,
        game_number = i,
        matchup = paste(game$away_team, "@", game$home_team),
        away_team = game$away_team,
        home_team = game$home_team,
        
        # Week 1: Predict home team wins with 2.5 point advantage
        predicted_winner = game$home_team,
        predicted_margin = 2.5,
        predicted_home_score = 24.0,
        predicted_away_score = 21.5,
        win_confidence = 0.55,
        
        # Vegas lines
        vegas_spread = game$spread_line,
        vegas_home_favorite = if_else(!is.na(game$spread_line), game$spread_line < 0, NA),
        
        # ATS prediction
        predicted_ats_winner = case_when(
          is.na(vegas_spread) ~ "NO LINE",
          predicted_margin > vegas_spread ~ game$home_team,
          predicted_margin < vegas_spread ~ game$away_team,
          TRUE ~ "PUSH"
        ),
        
        # Actual results
        game_completed = game$game_completed,
        actual_winner = game$actual_winner,
        actual_home_score = game$actual_home_score,
        actual_away_score = game$actual_away_score,
        actual_margin = game$actual_margin,
        
        # Correct predictions
        winner_correct = if_else(game_completed, predicted_winner == actual_winner, NA),
        ats_correct = case_when(
          !game_completed | is.na(vegas_spread) ~ NA,
          predicted_ats_winner == "PUSH" ~ NA,
          predicted_ats_winner == home_team & game$home_covered_spread == TRUE ~ TRUE,
          predicted_ats_winner == away_team & game$home_covered_spread == FALSE ~ TRUE,
          TRUE ~ FALSE
        )
      )
      
      all_week_predictions[[length(all_week_predictions) + 1]] <- prediction
    }
    
  } else {
    # Weeks 2+: Use data from previous weeks
    current_offense <- team_offense_rolling %>%
      filter(week < pred_week) %>%
      group_by(team_abbr) %>%
      arrange(desc(week)) %>%
      slice(1) %>%
      ungroup()
    
    current_defense <- team_defense_rolling %>%
      filter(week < pred_week) %>%
      group_by(team_abbr) %>%
      arrange(desc(week)) %>%
      slice(1) %>%
      ungroup()
    
    for (i in 1:nrow(week_games)) {
      game <- week_games[i, ]
      
      # Get team stats
      home_off <- current_offense %>% filter(team_abbr == game$home_team)
      away_off <- current_offense %>% filter(team_abbr == game$away_team)
      home_def <- current_defense %>% filter(team_abbr == game$home_team)
      away_def <- current_defense %>% filter(team_abbr == game$away_team)
      
      if (nrow(home_off) == 0 || nrow(away_off) == 0 || 
          nrow(home_def) == 0 || nrow(away_def) == 0) {
        # Fallback if no data
        home_advantage <- 0
        away_advantage <- 0
      } else {
        # Calculate matchup advantages
        home_epa <- coalesce(home_off$roll3_epa, home_off$season_avg_epa, 0)
        away_epa <- coalesce(away_off$roll3_epa, away_off$season_avg_epa, 0)
        home_def_epa <- coalesce(home_def$def_roll3_epa, home_def$def_season_avg_epa, 0)
        away_def_epa <- coalesce(away_def$def_roll3_epa, away_def$def_season_avg_epa, 0)
        
        home_advantage <- home_epa - away_def_epa
        away_advantage <- away_epa - home_def_epa
      }
      
      net_advantage <- home_advantage - away_advantage
      
      # Model predictions
      predicted_margin <- (net_advantage * 15) + 2.5  # Home field advantage
      predicted_home_score <- 24 + (home_advantage * 7)
      predicted_away_score <- 24 + (away_advantage * 7)
      
      # Win probability (logistic transform)
      win_prob <- 1 / (1 + exp(-predicted_margin / 14))
      
      # Predicted winner
      predicted_winner <- if_else(predicted_margin > 0, game$home_team, game$away_team)
      
      # ATS prediction
      predicted_ats_winner <- case_when(
        is.na(game$spread_line) ~ "NO LINE",
        abs(predicted_margin - game$spread_line) < 1 ~ "PUSH",
        predicted_margin > game$spread_line ~ game$home_team,
        predicted_margin < game$spread_line ~ game$away_team,
        TRUE ~ "PUSH"
      )
      
      prediction <- tibble(
        week = pred_week,
        game_number = i,
        matchup = paste(game$away_team, "@", game$home_team),
        away_team = game$away_team,
        home_team = game$home_team,
        
        # Predictions
        predicted_winner = predicted_winner,
        predicted_margin = predicted_margin,
        predicted_home_score = predicted_home_score,
        predicted_away_score = predicted_away_score,
        win_confidence = max(win_prob, 1 - win_prob),
        
        # Vegas lines
        vegas_spread = game$spread_line,
        vegas_home_favorite = if_else(!is.na(game$spread_line), game$spread_line < 0, NA),
        
        # ATS prediction
        predicted_ats_winner = predicted_ats_winner,
        
        # Actual results
        game_completed = game$game_completed,
        actual_winner = game$actual_winner,
        actual_home_score = game$actual_home_score,
        actual_away_score = game$actual_away_score,
        actual_margin = game$actual_margin,
        
        # Correct predictions
        winner_correct = if_else(game_completed, predicted_winner == actual_winner, NA),
        ats_correct = case_when(
          !game_completed | is.na(vegas_spread) ~ NA,
          predicted_ats_winner == "PUSH" ~ NA,
          predicted_ats_winner == home_team & game$home_covered_spread == TRUE ~ TRUE,
          predicted_ats_winner == away_team & game$home_covered_spread == FALSE ~ TRUE,
          TRUE ~ FALSE
        )
      )
      
      all_week_predictions[[length(all_week_predictions) + 1]] <- prediction
    }
  }
}

predictions_all <- bind_rows(all_week_predictions)

cat("âœ“ Generated", nrow(predictions_all), "predictions\n\n")

# ============================================================================
# CALCULATE WEEKLY RECORDS
# ============================================================================

cat("Calculating weekly records...\n")

weekly_records <- predictions_all %>%
  filter(game_completed) %>%
  group_by(week) %>%
  summarise(
    games = n(),
    
    # Winner predictions
    winner_correct = sum(winner_correct, na.rm = TRUE),
    winner_incorrect = sum(!winner_correct, na.rm = TRUE),
    winner_pct = mean(winner_correct, na.rm = TRUE),
    
    # ATS predictions
    ats_games = sum(!is.na(ats_correct)),
    ats_correct = sum(ats_correct, na.rm = TRUE),
    ats_incorrect = sum(!ats_correct, na.rm = TRUE),
    ats_pct = if_else(ats_games > 0, ats_correct / ats_games, NA_real_),
    
    .groups = "drop"
  ) %>%
  mutate(
    # Running totals
    winner_running_correct = cumsum(winner_correct),
    winner_running_incorrect = cumsum(winner_incorrect),
    winner_running_pct = winner_running_correct / (winner_running_correct + winner_running_incorrect),
    
    ats_running_correct = cumsum(ats_correct),
    ats_running_incorrect = cumsum(ats_incorrect),
    ats_running_pct = ats_running_correct / (ats_running_correct + ats_running_incorrect),
    
    # Formatted records
    winner_record = paste0(winner_correct, "-", winner_incorrect),
    winner_running_record = paste0(winner_running_correct, "-", winner_running_incorrect),
    ats_record = paste0(ats_correct, "-", ats_incorrect),
    ats_running_record = paste0(ats_running_correct, "-", ats_running_incorrect)
  )

# Overall record
overall_record <- weekly_records %>%
  summarise(
    total_games = sum(games),
    winner_correct = sum(winner_correct),
    winner_incorrect = sum(winner_incorrect),
    winner_pct = winner_correct / (winner_correct + winner_incorrect),
    ats_correct = sum(ats_correct),
    ats_incorrect = sum(ats_incorrect),
    ats_pct = ats_correct / (ats_correct + ats_incorrect)
  )

cat("âœ“ Records calculated\n\n")

# ============================================================================
# EXPORT RESULTS
# ============================================================================

cat("Exporting tracking data...\n")

tracker_dir <- file.path(BASE_DIR, paste0('season', SEASON, '_analysis'), 'weekly_tracker')
if (!dir.exists(tracker_dir)) {
  dir.create(tracker_dir, recursive = TRUE)
}

# Create formatted output
predictions_formatted <- predictions_all %>%
  mutate(
    # Format scores
    predicted_score = paste0(home_team, " ", round(predicted_home_score, 1), 
                             " - ", away_team, " ", round(predicted_away_score, 1)),
    actual_score = if_else(
      game_completed,
      paste0(home_team, " ", actual_home_score, " - ", away_team, " ", actual_away_score),
      "NOT PLAYED"
    ),
    
    # Format predictions
    winner_prediction = paste0(predicted_winner, " (", round(win_confidence * 100, 1), "%)"),
    ats_prediction = if_else(predicted_ats_winner == "NO LINE", "NO LINE", 
                             paste0(predicted_ats_winner, " vs ", round(vegas_spread, 1))),
    
    # Results
    winner_result = case_when(
      !game_completed ~ "PENDING",
      winner_correct == TRUE ~ "CORRECT",
      winner_correct == FALSE ~ "WRONG",
      TRUE ~ "N/A"
    ),
    
    ats_result = case_when(
      !game_completed ~ "PENDING",
      is.na(ats_correct) ~ "PUSH/NO LINE",
      ats_correct == TRUE ~ "COVERED",
      ats_correct == FALSE ~ "MISSED",
      TRUE ~ "N/A"
    )
  ) %>%
  select(
    Week = week,
    Game = game_number,
    Matchup = matchup,
    `Predicted Winner` = winner_prediction,
    `ATS Pick` = ats_prediction,
    `Vegas Spread` = vegas_spread,
    `Predicted Score` = predicted_score,
    `Actual Score` = actual_score,
    `Winner Result` = winner_result,
    `ATS Result` = ats_result,
    Completed = game_completed
  )

# Export to Excel
writexl::write_xlsx(
  list(
    Overall_Record = overall_record,
    Weekly_Records = weekly_records,
    All_Predictions = predictions_formatted,
    Raw_Data = predictions_all
  ),
  file.path(tracker_dir, "season_prediction_tracker.xlsx")
)

# Export CSVs
write.csv(weekly_records, file.path(tracker_dir, "weekly_records.csv"), row.names = FALSE)
write.csv(predictions_formatted, file.path(tracker_dir, "all_predictions_formatted.csv"), row.names = FALSE)

cat("âœ“ Exported to Excel and CSV\n\n")

# ============================================================================
# CREATE VISUALIZATIONS
# ============================================================================

cat("Creating visualizations...\n")

# 1. Weekly win percentage
weekly_plot <- ggplot(weekly_records, aes(x = week)) +
  geom_line(aes(y = winner_pct, color = "Winner"), linewidth = 1.5) +
  geom_line(aes(y = ats_pct, color = "ATS"), linewidth = 1.5) +
  geom_point(aes(y = winner_pct, color = "Winner"), size = 3) +
  geom_point(aes(y = ats_pct, color = "ATS"), size = 3) +
  geom_hline(yintercept = 0.5, linetype = "dashed", color = "gray50") +
  scale_color_manual(values = c("Winner" = "#2ecc71", "ATS" = "#3498db")) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  labs(
    title = "Weekly Prediction Accuracy",
    subtitle = paste("Weeks", START_WEEK, "-", CURRENT_WEEK),
    x = "Week",
    y = "Win Percentage",
    color = "Prediction Type"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5),
    legend.position = "bottom"
  )

ggsave(file.path(tracker_dir, "weekly_accuracy.png"), weekly_plot, width = 12, height = 6, dpi = 300)

# 2. Running record
running_plot <- ggplot(weekly_records, aes(x = week)) +
  geom_line(aes(y = winner_running_pct, color = "Winner"), linewidth = 1.5) +
  geom_line(aes(y = ats_running_pct, color = "ATS"), linewidth = 1.5) +
  geom_point(aes(y = winner_running_pct, color = "Winner"), size = 3) +
  geom_point(aes(y = ats_running_pct, color = "ATS"), size = 3) +
  geom_hline(yintercept = 0.5, linetype = "dashed", color = "gray50") +
  geom_hline(yintercept = 0.526, linetype = "dashed", color = "red", alpha = 0.5) +
  annotate("text", x = max(weekly_records$week), y = 0.535, 
           label = "Breakeven (52.6%)", color = "red", size = 3) +
  scale_color_manual(values = c("Winner" = "#2ecc71", "ATS" = "#3498db")) +
  scale_y_continuous(labels = scales::percent, limits = c(0.4, 0.75)) +
  labs(
    title = "Running Win Percentage",
    subtitle = "Cumulative accuracy over the season",
    x = "Week",
    y = "Running Win %",
    color = "Prediction Type"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5),
    legend.position = "bottom"
  )

ggsave(file.path(tracker_dir, "running_record.png"), running_plot, width = 12, height = 6, dpi = 300)

cat("âœ“ Visualizations saved\n\n")

# ============================================================================
# PRINT RESULTS
# ============================================================================

cat("â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—\n")
cat("â•‘  SEASON PREDICTION TRACKER - RESULTS                           â•‘\n")
cat("â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•\n\n")

cat("ðŸ“Š OVERALL RECORD (Weeks", START_WEEK, "-", CURRENT_WEEK, "):\n")
cat("â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•\n")
cat(sprintf("Winner Predictions: %d-%d (%.1f%%)\n", 
            overall_record$winner_correct,
            overall_record$winner_incorrect,
            overall_record$winner_pct * 100))
cat(sprintf("ATS Predictions:    %d-%d (%.1f%%)\n", 
            overall_record$ats_correct,
            overall_record$ats_incorrect,
            overall_record$ats_pct * 100))
cat(sprintf("Total Games:        %d\n\n", overall_record$total_games))

if (overall_record$ats_pct >= 0.526) {
  cat("âœ… BEATING THE SPREAD! (Need 52.6% to be profitable)\n\n")
} else {
  cat("âŒ Below breakeven (Need 52.6% to beat the vig)\n\n")
}

cat("ðŸ“… WEEK-BY-WEEK BREAKDOWN:\n")
cat("â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•\n")
cat(sprintf("%-6s %-12s %-15s %-12s %-15s\n", "Week", "Winner", "Running", "ATS", "Running"))
cat("â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€\n")

for (i in 1:nrow(weekly_records)) {
  wk <- weekly_records[i, ]
  cat(sprintf("%-6d %-12s %-15s %-12s %-15s\n",
              wk$week,
              paste0(wk$winner_record, " (", round(wk$winner_pct * 100, 1), "%)"),
              paste0(wk$winner_running_record, " (", round(wk$winner_running_pct * 100, 1), "%)"),
              paste0(wk$ats_record, " (", round(wk$ats_pct * 100, 1), "%)"),
              paste0(wk$ats_running_record, " (", round(wk$ats_running_pct * 100, 1), "%)")))
}

cat("\nðŸ“ Files saved to:", tracker_dir, "\n")
cat("   â€¢ season_prediction_tracker.xlsx (All tabs)\n")
cat("   â€¢ weekly_records.csv\n")
cat("   â€¢ all_predictions_formatted.csv\n")
cat("   â€¢ weekly_accuracy.png\n")
cat("   â€¢ running_record.png\n\n")

cat("âœ… Season tracking complete!\n\n")
