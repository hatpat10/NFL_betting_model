# ============================================================================
# NFL MODEL BACKTESTING - 2025 SEASON (WEEKS 5-10)
# ============================================================================
# Evaluates model predictions against historical betting lines and actual results
# for the 2025 NFL season from Week 5 through Week 10
# ============================================================================

library(tidyverse)
library(nflreadr)
library(DBI)
library(RSQLite)

# Configuration for 2025 Season
SEASON <- 2025
START_WEEK <- 5
CURRENT_WEEK <- 10  # Current week as of now
MODEL_DIR <- "reports"
DB_PATH <- "db/nfl_odds_2025.sqlite"

cat("\n", strrep("=", 70), "\n", sep = "")
cat("NFL 2025 SEASON - MODEL BACKTESTING\n")
cat("Evaluating Weeks", START_WEEK, "through", CURRENT_WEEK, "\n")
cat(strrep("=", 70), "\n\n")

# ============================================================================
# LOAD ACTUAL GAME RESULTS FOR 2025
# ============================================================================

cat("Loading actual game results for 2025 season...\n")

actual_results <- load_schedules(SEASON) %>%
  filter(
    week >= START_WEEK,
    week <= CURRENT_WEEK,
    game_type == "REG",
    !is.na(result)  # Only completed games
  ) %>%
  select(
    season, week, game_id,
    home_team, away_team,
    home_score, away_score,
    result,  # Home team margin
    total,   # Total points
    gameday, gametime
  ) %>%
  mutate(
    matchup_key = paste(away_team, "at", home_team),
    actual_margin = home_score - away_score,
    actual_total = home_score + away_score
  )

cat("✓ Loaded", nrow(actual_results), "completed games from Weeks", 
    START_WEEK, "-", CURRENT_WEEK, "\n\n")

# ============================================================================
# LOAD HISTORICAL ODDS FROM SPORTSDATA.IO DATABASE
# ============================================================================

cat("Loading historical betting lines from SportsData.io database...\n")

if (!file.exists(DB_PATH)) {
  cat("✗ Database not found. Run fetch_2025_season_odds.R first to get SportsData.io odds\n")
  stop("Missing odds database - need to fetch from SportsData.io first")
}

con <- dbConnect(SQLite(), DB_PATH)

# Get consensus odds for Weeks 5-10
consensus_odds <- dbGetQuery(con, "
  SELECT 
    game_key,
    week,
    home_team_abbr as home_team,
    away_team_abbr as away_team,
    
    -- Consensus lines (average across all sportsbooks)
    ROUND(AVG(home_spread), 1) as vegas_spread,
    ROUND(AVG(over_under), 1) as vegas_total,
    ROUND(AVG(home_moneyline), 0) as home_ml,
    ROUND(AVG(away_moneyline), 0) as away_ml,
    
    -- Spread variance info
    ROUND(STDEV(home_spread), 2) as spread_std,
    ROUND(MIN(home_spread), 1) as spread_best,
    ROUND(MAX(home_spread), 1) as spread_worst,
    
    -- Number of books
    COUNT(DISTINCT sportsbook) as n_books,
    GROUP_CONCAT(DISTINCT sportsbook) as books_list
    
  FROM historical_odds_2025
  WHERE season = ? AND week BETWEEN ? AND ?
  GROUP BY game_key, week, home_team_abbr, away_team_abbr
  ORDER BY week, game_key
", params = list(SEASON, START_WEEK, CURRENT_WEEK))

dbDisconnect(con)

consensus_odds <- consensus_odds %>%
  mutate(matchup_key = paste(away_team, "at", home_team))

cat("✓ Loaded odds for", nrow(consensus_odds), "games\n")
cat("  Sportsbooks included:", length(unique(unlist(strsplit(consensus_odds$books_list, ",")))), "\n\n")

# ============================================================================
# MERGE RESULTS WITH ODDS
# ============================================================================

games_with_odds <- actual_results %>%
  inner_join(
    consensus_odds %>% select(-game_key),
    by = c("week", "matchup_key", "home_team", "away_team")
  ) %>%
  mutate(
    # ATS results
    home_cover = actual_margin + vegas_spread > 0,
    away_cover = !home_cover,
    
    # O/U results
    over = actual_total > vegas_total,
    under = actual_total < vegas_total,
    
    # Favorite/Dog
    favorite = ifelse(vegas_spread < 0, home_team, away_team),
    underdog = ifelse(vegas_spread < 0, away_team, home_team),
    favorite_covered = ifelse(vegas_spread < 0, home_cover, away_cover)
  )

cat("✓ Successfully matched", nrow(games_with_odds), "games with odds\n\n")

# ============================================================================
# LOAD MODEL PREDICTIONS FOR EACH WEEK
# ============================================================================

cat("Loading model predictions for Weeks", START_WEEK, "-", CURRENT_WEEK, "...\n")

all_predictions <- list()
missing_weeks <- c()

for (week in START_WEEK:CURRENT_WEEK) {
  
  # Try multiple file naming patterns
  pred_files <- c(
    file.path(MODEL_DIR, paste0("week_", SEASON, "_", week, "_predictions.csv")),
    file.path(MODEL_DIR, paste0("predictions_week_", week, ".csv")),
    file.path(MODEL_DIR, paste0("week", week, "_predictions.csv"))
  )
  
  file_found <- FALSE
  for (pred_file in pred_files) {
    if (file.exists(pred_file)) {
      predictions <- read_csv(pred_file, show_col_types = FALSE) %>%
        mutate(
          week = week,
          matchup_key = paste(away_team, "at", home_team),
          model_spread = -predicted_margin  # Convert to home spread
        )
      all_predictions[[length(all_predictions) + 1]] <- predictions
      cat("  Week", week, "✓ -", nrow(predictions), "predictions loaded\n")
      file_found <- TRUE
      break
    }
  }
  
  if (!file_found) {
    cat("  Week", week, "✗ - No prediction file found\n")
    missing_weeks <- c(missing_weeks, week)
  }
}

if (length(all_predictions) == 0) {
  cat("\n❌ No model predictions found. Please ensure prediction files exist in:", MODEL_DIR, "\n")
  cat("Expected format: week_2025_[week]_predictions.csv\n")
  stop("No predictions to evaluate")
}

# Combine all predictions
model_predictions <- bind_rows(all_predictions)
cat("\n✓ Loaded", nrow(model_predictions), "total predictions\n\n")

# ============================================================================
# EVALUATE MODEL PERFORMANCE
# ============================================================================

cat(strrep("=", 70), "\n")
cat("MODEL PERFORMANCE EVALUATION\n")
cat(strrep("=", 70), "\n\n")

# Merge predictions with actual results and odds
evaluation <- games_with_odds %>%
  inner_join(
    model_predictions %>% 
      select(week, matchup_key, predicted_margin, model_spread, 
             home_win_prob, predicted_total),
    by = c("week", "matchup_key")
  ) %>%
  mutate(
    # Spread betting analysis
    spread_edge = model_spread - vegas_spread,
    spread_edge_abs = abs(spread_edge),
    
    # Model's bet recommendation
    model_bet = case_when(
      spread_edge > 1.5 ~ home_team,  # Bet home if model likes them by 1.5+
      spread_edge < -1.5 ~ away_team,  # Bet away if model likes them by 1.5+
      TRUE ~ "PASS"
    ),
    
    # Did model's bet win?
    model_bet_won = case_when(
      model_bet == home_team & home_cover ~ TRUE,
      model_bet == away_team & away_cover ~ TRUE,
      model_bet == "PASS" ~ NA,
      TRUE ~ FALSE
    ),
    
    # Margin prediction accuracy
    margin_error = predicted_margin - actual_margin,
    margin_abs_error = abs(margin_error),
    
    # Total prediction accuracy
    total_error = predicted_total - actual_total,
    total_abs_error = abs(total_error),
    
    # Straight up winner accuracy
    predicted_winner = ifelse(home_win_prob > 0.5, home_team, away_team),
    actual_winner = ifelse(actual_margin > 0, home_team, away_team),
    correct_winner = predicted_winner == actual_winner
  )

# ============================================================================
# PERFORMANCE METRICS BY WEEK
# ============================================================================

cat("WEEK-BY-WEEK PERFORMANCE:\n")
cat(strrep("-", 60), "\n")

weekly_performance <- evaluation %>%
  group_by(week) %>%
  summarize(
    games = n(),
    
    # Straight up
    winner_accuracy = mean(correct_winner) * 100,
    
    # Spread betting
    bets_made = sum(model_bet != "PASS"),
    bets_won = sum(model_bet_won, na.rm = TRUE),
    ats_winrate = ifelse(bets_made > 0, bets_won / bets_made * 100, NA),
    
    # Prediction accuracy
    mae_margin = mean(margin_abs_error),
    mae_total = mean(total_abs_error),
    
    .groups = 'drop'
  )

print(weekly_performance)

# ============================================================================
# OVERALL PERFORMANCE SUMMARY
# ============================================================================

cat("\n", strrep("=", 70), "\n", sep = "")
cat("OVERALL PERFORMANCE (Weeks", START_WEEK, "-", CURRENT_WEEK, ")\n")
cat(strrep("=", 70), "\n\n")

overall_stats <- evaluation %>%
  summarize(
    total_games = n(),
    
    # Straight up accuracy
    winner_accuracy = mean(correct_winner) * 100,
    
    # ATS performance
    total_bets = sum(model_bet != "PASS"),
    bets_won = sum(model_bet_won, na.rm = TRUE),
    ats_winrate = bets_won / total_bets * 100,
    
    # Margin accuracy
    mae_margin = mean(margin_abs_error),
    rmse_margin = sqrt(mean(margin_error^2)),
    
    # Total accuracy
    mae_total = mean(total_abs_error),
    rmse_total = sqrt(mean(total_error^2))
  )

cat("Games Evaluated:         ", overall_stats$total_games, "\n")
cat("\n")
cat("WINNER PREDICTION:\n")
cat(sprintf("  Accuracy:              %.1f%%\n", overall_stats$winner_accuracy))
cat("\n")
cat("ATS BETTING:\n")
cat(sprintf("  Total Bets:            %d\n", overall_stats$total_bets))
cat(sprintf("  Bets Won:              %d\n", overall_stats$bets_won))
cat(sprintf("  Win Rate:              %.1f%%\n", overall_stats$ats_winrate))
cat("\n")
cat("MARGIN PREDICTION:\n")
cat(sprintf("  MAE:                   %.2f points\n", overall_stats$mae_margin))
cat(sprintf("  RMSE:                  %.2f points\n", overall_stats$rmse_margin))
cat("\n")
cat("TOTAL PREDICTION:\n")
cat(sprintf("  MAE:                   %.2f points\n", overall_stats$mae_total))
cat(sprintf("  RMSE:                  %.2f points\n", overall_stats$rmse_total))

# ============================================================================
# PERFORMANCE BY EDGE SIZE
# ============================================================================

cat("\n\nPERFORMANCE BY EDGE SIZE:\n")
cat(strrep("-", 60), "\n")

edge_performance <- evaluation %>%
  filter(model_bet != "PASS") %>%
  mutate(
    edge_bucket = case_when(
      spread_edge_abs >= 5 ~ "5+ points",
      spread_edge_abs >= 3 ~ "3-5 points",
      spread_edge_abs >= 1.5 ~ "1.5-3 points",
      TRUE ~ "< 1.5 points"
    )
  ) %>%
  group_by(edge_bucket) %>%
  summarize(
    n_bets = n(),
    n_won = sum(model_bet_won),
    win_rate = mean(model_bet_won) * 100,
    avg_edge = mean(spread_edge_abs),
    .groups = 'drop'
  ) %>%
  arrange(desc(avg_edge))

print(edge_performance)

# ============================================================================
# TOP EDGES ANALYSIS
# ============================================================================

cat("\n\nTOP 10 EDGES (Model vs Vegas):\n")
cat(strrep("-", 60), "\n")

top_edges <- evaluation %>%
  filter(model_bet != "PASS") %>%
  arrange(desc(spread_edge_abs)) %>%
  head(10) %>%
  select(
    week, matchup_key, 
    model_spread, vegas_spread, spread_edge,
    model_bet, actual_margin, model_bet_won
  ) %>%
  mutate(
    result = ifelse(model_bet_won, "✓ WON", "✗ LOST")
  )

print(top_edges)

# ============================================================================
# CLOSING LINE VALUE (CLV) ANALYSIS
# ============================================================================

cat("\n\nCLOSING LINE VALUE ANALYSIS:\n")
cat(strrep("-", 60), "\n")

# For CLV, we'd need opening vs closing lines
# This is a simplified version assuming consensus = closing
clv_analysis <- evaluation %>%
  filter(model_bet != "PASS") %>%
  mutate(
    # Positive CLV means line moved in our favor
    clv = case_when(
      model_bet == home_team ~ -(vegas_spread - model_spread),  
      model_bet == away_team ~ (vegas_spread - model_spread),
      TRUE ~ 0
    )
  ) %>%
  summarize(
    avg_clv = mean(clv),
    positive_clv_pct = mean(clv > 0) * 100,
    median_clv = median(clv)
  )

cat(sprintf("  Average CLV:           %.2f points\n", clv_analysis$avg_clv))
cat(sprintf("  Positive CLV%%:         %.1f%%\n", clv_analysis$positive_clv_pct))
cat(sprintf("  Median CLV:            %.2f points\n", clv_analysis$median_clv))

# ============================================================================
# SAVE DETAILED RESULTS
# ============================================================================

output_file <- paste0("reports/backtest_results_2025_weeks_", START_WEEK, "_", CURRENT_WEEK, ".csv")
write_csv(evaluation, output_file)

cat("\n", strrep("=", 70), "\n", sep = "")
cat("✓ BACKTESTING COMPLETE\n")
cat("  Weeks Evaluated: ", START_WEEK, "-", CURRENT_WEEK, "\n")
cat("  Detailed results saved to: ", output_file, "\n")
cat(strrep("=", 70), "\n")

# ============================================================================
# PLOT PERFORMANCE TRENDS
# ============================================================================

if (require(ggplot2, quietly = TRUE)) {
  
  # Weekly ATS performance plot
  p1 <- ggplot(weekly_performance, aes(x = week, y = ats_winrate)) +
    geom_line(size = 1.2, color = "blue") +
    geom_point(size = 3, color = "blue") +
    geom_hline(yintercept = 52.38, linetype = "dashed", color = "red") +
    labs(title = "ATS Win Rate by Week (2025 Season)",
         subtitle = "Red line = 52.38% break-even",
         x = "Week", y = "ATS Win Rate (%)") +
    theme_minimal() +
    scale_x_continuous(breaks = START_WEEK:CURRENT_WEEK)
  
  ggsave("reports/ats_performance_2025.png", p1, width = 10, height = 6)
  cat("\n✓ Performance plot saved to: reports/ats_performance_2025.png\n")
}