# ============================================================================
# NFL MODEL BACKTEST - FIXED FOR ACTUAL PIPELINE OUTPUT (v4.0)
# ============================================================================
# Tests YOUR EPA-based predictions against actual game results
# FIXED: Compatible with og_pipeline.R and og_odds.R outputs
# 
# This version:
#   - Works with your actual file structure
#   - Handles missing 'week' column (adds it)
#   - Calculates ATS performance vs Vegas lines
#   - Validates betting edges
# ============================================================================

library(dplyr)
library(tidyr)
library(nflreadr)
library(ggplot2)
library(writexl)

# ============================================================================
# CONFIGURATION
# ============================================================================

BASE_DIR <- "C:/Users/Patsc/Documents/NFL_betting_model"  # FIXED: Match your pipeline
BACKTEST_WEEKS <- 5:9  # Weeks to test
SEASON <- 2025
BET_SIZE <- 100  # $100 per bet for simulation
MIN_EDGE <- 1.5  # Only bet when edge >= 1.5 pts

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║  BACKTEST - PIPELINE VALIDATION (v4.0 - FIXED)                ║\n")
cat("║  Testing Weeks:", paste(BACKTEST_WEEKS, collapse = ", "), "                                            ║\n")
cat("║  Base Directory:", BASE_DIR, "                      ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Create backtest directory
backtest_dir <- file.path(BASE_DIR, "backtest_results")
dir.create(backtest_dir, showWarnings = FALSE, recursive = TRUE)

# ============================================================================
# STEP 1: LOAD ACTUAL GAME RESULTS
# ============================================================================

cat("[1/7] Loading actual game results from nflreadr...\n")

actuals <- load_pbp(SEASON) %>%
  filter(
    season_type == "REG",
    week %in% BACKTEST_WEEKS,
    !is.na(home_score),
    !is.na(away_score)
  ) %>%
  group_by(game_id, week, home_team, away_team) %>%
  summarise(
    actual_home_score = max(home_score, na.rm = TRUE),
    actual_away_score = max(away_score, na.rm = TRUE),
    .groups = 'drop'
  ) %>%
  mutate(
    actual_margin = actual_home_score - actual_away_score,  # Positive = home won
    actual_winner = if_else(actual_margin > 0, home_team, away_team),
    actual_total = actual_home_score + actual_away_score,
    home_won = actual_home_score > actual_away_score,
    matchup_key = paste(away_team, "at", home_team)
  )

cat("  ✓ Loaded", nrow(actuals), "completed games\n")
cat("    Weeks covered:", paste(sort(unique(actuals$week)), collapse = ", "), "\n\n")

# ============================================================================
# STEP 2: LOAD MODEL PREDICTIONS
# ============================================================================

cat("[2/7] Loading predictions from pipeline...\n")

load_week_predictions <- function(week_num) {
  
  week_dir <- file.path(BASE_DIR, paste0('week', week_num), 'matchup_analysis')
  pred_file <- file.path(week_dir, "betting_recommendations_enhanced.csv")
  
  if (!file.exists(pred_file)) {
    cat("  ⚠️  Week", week_num, "predictions not found\n")
    return(NULL)
  }
  
  tryCatch({
    preds <- read.csv(pred_file, stringsAsFactors = FALSE) %>%
      as_tibble()
    
    # Add week column if missing (common issue)
    if (!"week" %in% names(preds)) {
      preds <- preds %>% mutate(week = week_num)
      cat("  ⚠️  Added missing 'week' column to Week", week_num, "\n")
    }
    
    # Ensure required columns exist
    required_cols <- c("home_team", "away_team", "projected_margin")
    missing_cols <- setdiff(required_cols, names(preds))
    
    if (length(missing_cols) > 0) {
      cat("  ❌ Week", week_num, "missing columns:", paste(missing_cols, collapse = ", "), "\n")
      return(NULL)
    }
    
    cat("  ✓ Week", week_num, "loaded (", nrow(preds), "games)\n")
    return(preds)
    
  }, error = function(e) {
    cat("  ❌ Error reading Week", week_num, ":", e$message, "\n")
    return(NULL)
  })
}

# Load all weeks
predictions_list <- list()
for (week_num in BACKTEST_WEEKS) {
  week_preds <- load_week_predictions(week_num)
  if (!is.null(week_preds)) {
    predictions_list[[as.character(week_num)]] <- week_preds
  }
}

if (length(predictions_list) == 0) {
  stop("\n❌ No predictions found! Run og_pipeline.R for weeks ", 
       paste(BACKTEST_WEEKS, collapse = ", "), " first.\n")
}

predictions <- bind_rows(predictions_list)

cat("\n  ✓ Total predictions loaded:", nrow(predictions), "\n")
cat("    Weeks with predictions:", paste(sort(unique(predictions$week)), collapse = ", "), "\n\n")

# ============================================================================
# STEP 3: LOAD VEGAS ODDS (FROM OG_ODDS.R OUTPUT)
# ============================================================================

cat("[3/7] Loading Vegas odds data...\n")

load_week_odds <- function(week_num) {
  
  odds_dir <- file.path(BASE_DIR, paste0('week', week_num), 'odds_analysis')
  odds_file <- file.path(odds_dir, "all_games_analysis.csv")
  
  if (!file.exists(odds_file)) {
    cat("  ⚠️  Week", week_num, "odds not found (run og_odds.R)\n")
    return(NULL)
  }
  
  tryCatch({
    odds <- read.csv(odds_file, stringsAsFactors = FALSE) %>%
      as_tibble() %>%
      mutate(week = week_num)
    
    cat("  ✓ Week", week_num, "odds loaded\n")
    return(odds)
    
  }, error = function(e) {
    cat("  ⚠️  Week", week_num, "odds error:", e$message, "\n")
    return(NULL)
  })
}

# Load odds for all weeks
odds_list <- list()
for (week_num in BACKTEST_WEEKS) {
  week_odds <- load_week_odds(week_num)
  if (!is.null(week_odds)) {
    odds_list[[as.character(week_num)]] <- week_odds
  }
}

if (length(odds_list) > 0) {
  vegas_odds <- bind_rows(odds_list)
  cat("\n  ✓ Vegas odds loaded for", length(unique(vegas_odds$week)), "weeks\n\n")
  has_vegas <- TRUE
} else {
  cat("\n  ⚠️  No Vegas odds found - will skip ATS analysis\n")
  cat("     Run og_odds.R for each week to get full analysis\n\n")
  vegas_odds <- NULL
  has_vegas <- FALSE
}

# ============================================================================
# STEP 4: JOIN PREDICTIONS WITH ACTUALS
# ============================================================================

cat("[4/7] Matching predictions to actual results...\n")

# Standardize matchup keys
predictions <- predictions %>%
  mutate(
    matchup_key = if ("game" %in% names(.)) game else paste(away_team, "at", home_team)
  )

# Join with actuals
comparison <- predictions %>%
  left_join(
    actuals %>% select(week, matchup_key, actual_home_score, actual_away_score,
                       actual_margin, actual_winner, actual_total, home_won),
    by = c("week", "matchup_key")
  ) %>%
  filter(!is.na(actual_margin))  # Only completed games

cat("  ✓ Matched", nrow(comparison), "predictions to actual results\n")

if (nrow(comparison) == 0) {
  stop("\n❌ No matches found! Check that:\n",
       "  1. Week numbers align between predictions and actuals\n",
       "  2. Team abbreviations match (e.g., LA vs LAR, LAC)\n",
       "  3. Games have been played\n")
}

# Add derived metrics
comparison <- comparison %>%
  mutate(
    # Winner prediction
    predicted_winner = if_else(projected_margin > 0, home_team, away_team),
    correct_winner = predicted_winner == actual_winner,
    
    # Margin accuracy
    margin_error = abs(projected_margin - actual_margin),
    squared_error = margin_error^2,
    prediction_bias = projected_margin - actual_margin,
    
    # Game categories
    close_game = abs(actual_margin) < 7,
    blowout = abs(actual_margin) >= 14,
    upset = (projected_margin > 0 & actual_margin < 0) | 
      (projected_margin < 0 & actual_margin > 0)
  )

cat("\n")

# ============================================================================
# STEP 5: ADD VEGAS ODDS & CALCULATE ATS PERFORMANCE
# ============================================================================

if (has_vegas) {
  cat("[5/7] Calculating ATS performance vs Vegas...\n")
  
  # Join with Vegas odds
  comparison <- comparison %>%
    left_join(
      vegas_odds %>% select(week, matchup_key, vegas_line, edge, 
                            over_under, sportsbook),
      by = c("week", "matchup_key")
    )
  
  # Calculate ATS metrics
  comparison <- comparison %>%
    mutate(
      # Model spread (negative of margin, because spread favors underdog)
      model_spread = -projected_margin,
      
      # Edge (already calculated in og_odds.R)
      edge = if_else(is.na(edge), model_spread - vegas_line, edge),
      
      # Which side did model recommend?
      model_pick_side = case_when(
        edge > 0 ~ "HOME",
        edge < 0 ~ "AWAY",
        TRUE ~ "PUSH"
      ),
      
      # ATS result (did the pick cover the Vegas spread?)
      ats_result = actual_margin + vegas_line,  # Positive = home covered
      covered = case_when(
        model_pick_side == "HOME" & ats_result > 0 ~ TRUE,
        model_pick_side == "AWAY" & ats_result < 0 ~ TRUE,
        TRUE ~ FALSE
      ),
      
      # Would we have bet this game?
      would_bet = abs(edge) >= MIN_EDGE,
      
      # ATS win if we bet and covered
      ats_win = would_bet & covered
    )
  
  ats_games <- comparison %>% filter(would_bet)
  
  cat("  ✓ ATS analysis complete\n")
  cat("    Games with edge ≥", MIN_EDGE, "pts:", nrow(ats_games), "\n")
  cat("    ATS hit rate:", 
      sprintf("%.1f%%", mean(ats_games$covered, na.rm = TRUE) * 100), "\n\n")
  
} else {
  cat("[5/7] Skipping ATS analysis (no Vegas odds)\n\n")
}

# ============================================================================
# STEP 6: CALCULATE PERFORMANCE METRICS
# ============================================================================

cat("[6/7] Calculating performance metrics...\n")

# Overall metrics
overall_metrics <- comparison %>%
  summarise(
    total_games = n(),
    
    # Winner prediction
    correct_winners = sum(correct_winner, na.rm = TRUE),
    hit_rate = mean(correct_winner, na.rm = TRUE),
    
    # Margin accuracy
    mean_abs_error = mean(margin_error, na.rm = TRUE),
    rmse = sqrt(mean(squared_error, na.rm = TRUE)),
    median_error = median(margin_error, na.rm = TRUE),
    bias = mean(prediction_bias, na.rm = TRUE),
    
    # By game type
    close_games = sum(close_game, na.rm = TRUE),
    close_hit_rate = mean(correct_winner[close_game], na.rm = TRUE),
    blowout_games = sum(blowout, na.rm = TRUE),
    blowout_hit_rate = mean(correct_winner[blowout], na.rm = TRUE),
    upsets = sum(upset, na.rm = TRUE)
  )

# By week
by_week <- comparison %>%
  group_by(week) %>%
  summarise(
    games = n(),
    hit_rate = mean(correct_winner, na.rm = TRUE),
    mae = mean(margin_error, na.rm = TRUE),
    .groups = 'drop'
  )

# By confidence (if available)
by_confidence <- NULL
if ("confidence" %in% names(comparison)) {
  by_confidence <- comparison %>%
    filter(!is.na(confidence)) %>%
    group_by(confidence) %>%
    summarise(
      games = n(),
      hit_rate = mean(correct_winner, na.rm = TRUE),
      mae = mean(margin_error, na.rm = TRUE),
      .groups = 'drop'
    )
}

# ATS metrics (if available)
ats_metrics <- NULL
if (has_vegas) {
  ats_metrics <- comparison %>%
    filter(would_bet) %>%
    summarise(
      total_bets = n(),
      ats_wins = sum(covered, na.rm = TRUE),
      ats_hit_rate = mean(covered, na.rm = TRUE),
      avg_edge = mean(abs(edge), na.rm = TRUE),
      max_edge = max(abs(edge), na.rm = TRUE)
    )
  
  # By edge bucket
  ats_by_edge <- comparison %>%
    filter(would_bet) %>%
    mutate(
      edge_bucket = case_when(
        abs(edge) >= 5 ~ "5+ pts",
        abs(edge) >= 3 ~ "3-5 pts",
        abs(edge) >= 2 ~ "2-3 pts",
        TRUE ~ "1.5-2 pts"
      )
    ) %>%
    group_by(edge_bucket) %>%
    summarise(
      bets = n(),
      ats_hit_rate = mean(covered, na.rm = TRUE),
      avg_edge = mean(abs(edge)),
      .groups = 'drop'
    ) %>%
    arrange(desc(avg_edge))
}

cat("  ✓ Metrics calculated\n\n")

# ============================================================================
# STEP 7: DISPLAY RESULTS
# ============================================================================

cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║  BACKTEST RESULTS                                              ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

cat("📊 OVERALL PERFORMANCE:\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat(sprintf("Total Games:         %d\n", overall_metrics$total_games))
cat(sprintf("Correct Winners:     %d (%.1f%%)\n", 
            overall_metrics$correct_winners, 
            overall_metrics$hit_rate * 100))

if (overall_metrics$hit_rate >= 0.60) {
  cat("  ✅ EXCELLENT - Strong predictive power\n")
} else if (overall_metrics$hit_rate >= 0.55) {
  cat("  ✅ GOOD - Solid edge\n")
} else if (overall_metrics$hit_rate >= 0.524) {
  cat("  ⚠️ MARGINAL - Barely profitable\n")
} else {
  cat("  ❌ BELOW BREAK-EVEN\n")
}

cat(sprintf("\nMean Abs Error:      %.2f points", overall_metrics$mean_abs_error))
if (overall_metrics$mean_abs_error < 10) {
  cat(" ✅\n")
} else {
  cat(" ⚠️\n")
}

cat(sprintf("RMSE:                %.2f points\n", overall_metrics$rmse))
cat(sprintf("Median Error:        %.2f points\n", overall_metrics$median_error))
cat(sprintf("Bias:                %+.2f points ", overall_metrics$bias))

if (abs(overall_metrics$bias) < 1) {
  cat("✅ (No systematic bias)\n")
} else if (overall_metrics$bias > 0) {
  cat("⚠️ (Over-predicting home teams)\n")
} else {
  cat("⚠️ (Under-predicting home teams)\n")
}

cat("\n📈 BY GAME TYPE:\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat(sprintf("Close Games (<7 pts): %d games, %.1f%% accuracy\n",
            overall_metrics$close_games, overall_metrics$close_hit_rate * 100))
cat(sprintf("Blowouts (≥14 pts):   %d games, %.1f%% accuracy\n",
            overall_metrics$blowout_games, overall_metrics$blowout_hit_rate * 100))
cat(sprintf("Upsets Predicted:     %d games\n", overall_metrics$upsets))

# ATS Performance
if (has_vegas && !is.null(ats_metrics)) {
  cat("\n💰 ATS BETTING PERFORMANCE:\n")
  cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
  cat(sprintf("Minimum Edge:        %.1f pts\n", MIN_EDGE))
  cat(sprintf("Bets Placed:         %d\n", ats_metrics$total_bets))
  cat(sprintf("ATS Wins:            %d\n", ats_metrics$ats_wins))
  cat(sprintf("ATS Hit Rate:        %.1f%% ", ats_metrics$ats_hit_rate * 100))
  
  if (ats_metrics$ats_hit_rate >= 0.56) {
    cat("🔥 EXCEPTIONAL\n")
  } else if (ats_metrics$ats_hit_rate >= 0.53) {
    cat("✅ PROFITABLE\n")
  } else if (ats_metrics$ats_hit_rate >= 0.524) {
    cat("⚠️ BREAK-EVEN\n")
  } else {
    cat("❌ LOSING\n")
  }
  
  cat(sprintf("Average Edge:        %.2f pts\n", ats_metrics$avg_edge))
  cat(sprintf("Max Edge:            %.2f pts\n", ats_metrics$max_edge))
  
  # ROI calculation
  wins <- ats_metrics$ats_wins
  losses <- ats_metrics$total_bets - ats_metrics$ats_wins
  profit <- (wins * (BET_SIZE * 100/110)) - (losses * BET_SIZE)
  roi <- (profit / (ats_metrics$total_bets * BET_SIZE)) * 100
  
  cat(sprintf("\nBet Size:            $%d per game\n", BET_SIZE))
  cat(sprintf("Total Risked:        $%d\n", ats_metrics$total_bets * BET_SIZE))
  cat(sprintf("Profit/Loss:         $%+.2f\n", profit))
  cat(sprintf("ROI:                 %+.1f%%\n", roi))
  
  if (profit > 0) {
    cat("  ✅ PROFITABLE STRATEGY\n")
  } else {
    cat("  ❌ LOSING STRATEGY\n")
  }
  
  # By edge bucket
  if (!is.null(ats_by_edge) && nrow(ats_by_edge) > 0) {
    cat("\n🎯 PERFORMANCE BY EDGE SIZE:\n")
    cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    for (i in 1:nrow(ats_by_edge)) {
      row <- ats_by_edge[i, ]
      cat(sprintf("%-10s: %2d bets, %.1f%% hit rate, %.2f avg edge\n",
                  row$edge_bucket, row$bets, row$ats_hit_rate * 100, row$avg_edge))
    }
  }
}

# By week
cat("\n📅 PERFORMANCE BY WEEK:\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
print(by_week %>%
        mutate(
          hit_rate = sprintf("%.1f%%", hit_rate * 100),
          mae = sprintf("%.2f", mae)
        ) %>%
        select(Week = week, Games = games, `Hit Rate` = hit_rate, MAE = mae),
      row.names = FALSE)

# By confidence
if (!is.null(by_confidence) && nrow(by_confidence) > 0) {
  cat("\n🎯 PERFORMANCE BY CONFIDENCE LEVEL:\n")
  cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
  print(by_confidence %>%
          mutate(
            hit_rate = sprintf("%.1f%%", hit_rate * 100),
            mae = sprintf("%.2f", mae)
          ) %>%
          select(Confidence = confidence, Games = games, 
                 `Hit Rate` = hit_rate, MAE = mae),
        row.names = FALSE)
}

# ============================================================================
# BIGGEST ERRORS
# ============================================================================

cat("\n\n🎯 BIGGEST PREDICTION ERRORS:\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

worst_misses <- comparison %>%
  arrange(desc(margin_error)) %>%
  head(5) %>%
  mutate(
    predicted_display = sprintf("%+.1f", projected_margin),
    actual_display = sprintf("%+.1f", actual_margin),
    error_display = sprintf("%.1f", margin_error)
  ) %>%
  select(Week = week, Matchup = matchup_key, 
         Predicted = predicted_display, Actual = actual_display, 
         Error = error_display)

print(worst_misses, row.names = FALSE)

# ============================================================================
# SAVE RESULTS
# ============================================================================

cat("\n\n💾 Saving results...\n")

# Excel workbook
output_sheets <- list(
  Summary = tibble(
    Metric = c("Total Games", "Hit Rate", "MAE", "RMSE", "Bias"),
    Value = c(
      overall_metrics$total_games,
      sprintf("%.1f%%", overall_metrics$hit_rate * 100),
      sprintf("%.2f", overall_metrics$mean_abs_error),
      sprintf("%.2f", overall_metrics$rmse),
      sprintf("%+.2f", overall_metrics$bias)
    )
  ),
  Details = comparison %>%
    select(week, matchup_key, projected_margin, actual_margin, margin_error,
           correct_winner, predicted_winner, actual_winner, 
           any_of(c("confidence", "vegas_line", "edge", "covered"))),
  By_Week = by_week
)

if (!is.null(by_confidence)) {
  output_sheets$By_Confidence <- by_confidence
}

if (has_vegas && !is.null(ats_metrics)) {
  output_sheets$ATS_Summary <- tibble(
    Metric = c("Total Bets", "ATS Wins", "ATS Hit Rate", "Avg Edge", "ROI"),
    Value = c(
      ats_metrics$total_bets,
      ats_metrics$ats_wins,
      sprintf("%.1f%%", ats_metrics$ats_hit_rate * 100),
      sprintf("%.2f", ats_metrics$avg_edge),
      sprintf("%+.1f%%", roi)
    )
  )
  
  if (!is.null(ats_by_edge)) {
    output_sheets$ATS_By_Edge <- ats_by_edge
  }
}

write_xlsx(output_sheets, file.path(backtest_dir, "backtest_results.xlsx"))

# Save detailed CSVs
write.csv(comparison, file.path(backtest_dir, "backtest_detailed.csv"), row.names = FALSE)
write.csv(by_week, file.path(backtest_dir, "backtest_by_week.csv"), row.names = FALSE)

cat("  ✓ Results saved to:", backtest_dir, "\n\n")

# ============================================================================
# CREATE VISUALIZATIONS
# ============================================================================

cat("📊 Creating visualizations...\n")

# 1. Scatter plot
accuracy_plot <- ggplot(comparison, aes(x = actual_margin, y = projected_margin)) +
  geom_point(aes(color = correct_winner), size = 3, alpha = 0.7) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "red", size = 1) +
  geom_hline(yintercept = 0, linetype = "dotted", alpha = 0.5) +
  geom_vline(xintercept = 0, linetype = "dotted", alpha = 0.5) +
  scale_color_manual(
    values = c("TRUE" = "#27ae60", "FALSE" = "#e74c3c"),
    labels = c("TRUE" = "Correct Winner", "FALSE" = "Wrong Winner")
  ) +
  labs(
    title = "NFL Model Prediction Accuracy",
    subtitle = sprintf("Hit Rate: %.1f%% | MAE: %.2f pts | RMSE: %.2f pts",
                       overall_metrics$hit_rate * 100,
                       overall_metrics$mean_abs_error,
                       overall_metrics$rmse),
    x = "Actual Margin (Positive = Home Won)",
    y = "Predicted Margin",
    color = "Prediction"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5, size = 16),
    plot.subtitle = element_text(hjust = 0.5, size = 11),
    legend.position = "bottom"
  )

ggsave(
  file.path(backtest_dir, "accuracy_scatter.png"),
  accuracy_plot,
  width = 10,
  height = 8,
  dpi = 300
)

cat("  ✓ Scatter plot saved\n")

# 2. Weekly performance
weekly_plot <- ggplot(by_week, aes(x = as.factor(week), y = hit_rate, group = 1)) +
  geom_line(color = "#3498db", size = 1.2) +
  geom_point(size = 3, color = "#3498db") +
  geom_hline(yintercept = 0.524, linetype = "dashed", color = "red") +
  scale_y_continuous(labels = scales::percent, limits = c(0.3, 1)) +
  labs(
    title = "Weekly Hit Rate Performance",
    subtitle = "Red line = Break-even threshold (52.4%)",
    x = "Week",
    y = "Hit Rate"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5)
  )

ggsave(
  file.path(backtest_dir, "weekly_performance.png"),
  weekly_plot,
  width = 10,
  height = 6,
  dpi = 300
)

cat("  ✓ Weekly plot saved\n\n")

# ============================================================================
# FINAL SUMMARY
# ============================================================================

cat("════════════════════════════════════════════════════════════════\n")
cat("🎉 BACKTEST COMPLETE!\n")
cat("════════════════════════════════════════════════════════════════\n\n")

cat("📁 Results saved to:", backtest_dir, "\n\n")

cat("📄 FILES CREATED:\n")
cat("  • backtest_results.xlsx (all sheets)\n")
cat("  • backtest_detailed.csv\n")
cat("  • backtest_by_week.csv\n")
cat("  • accuracy_scatter.png\n")
cat("  • weekly_performance.png\n\n")

cat("════════════════════════════════════════════════════════════════\n")
cat("RECOMMENDATIONS:\n")
cat("════════════════════════════════════════════════════════════════\n\n")

if (has_vegas && !is.null(ats_metrics)) {
  if (ats_metrics$ats_hit_rate >= 0.56) {
    cat("🔥 EXCEPTIONAL ATS PERFORMANCE\n")
    cat(sprintf("   %.1f%% hit rate at %.2f pt avg edge\n", 
                ats_metrics$ats_hit_rate * 100, ats_metrics$avg_edge))
    cat("   Next steps:\n")
    cat("   1. Continue tracking 2-3 more weeks\n")
    cat("   2. Paper trade to validate\n")
    cat("   3. Define strict bankroll management\n")
    cat("   4. Consider graduated real money testing\n\n")
  } else if (ats_metrics$ats_hit_rate >= 0.53) {
    cat("✅ PROFITABLE ATS PERFORMANCE\n")
    cat(sprintf("   %.1f%% hit rate - solid edge confirmed\n", 
                ats_metrics$ats_hit_rate * 100))
    cat("   Next steps:\n")
    cat("   1. Backtest more weeks for confirmation\n")
    cat("   2. Paper trade for validation\n")
    cat("   3. Focus on highest edge bets (≥3 pts)\n\n")
  } else if (ats_metrics$ats_hit_rate >= 0.524) {
    cat("⚠️ MARGINAL ATS EDGE\n")
    cat("   Hit rate barely above break-even\n")
    cat("   DO NOT bet real money yet\n")
    cat("   Need larger sample size\n\n")
  } else {
    cat("❌ UNPROFITABLE ATS PERFORMANCE\n")
    cat("   Model edges not translating to winning bets\n")
    cat("   Critical issues to address:\n")
    cat("   1. Edge calculation may be wrong\n")
    cat("   2. Model may be miscalibrated\n")
    cat("   3. Need to review feature weights\n\n")
  }
} else {
  if (overall_metrics$hit_rate >= 0.55) {
    cat("✅ GOOD WINNER PREDICTION\n")
    cat(sprintf("   %.1f%% hit rate\n", overall_metrics$hit_rate * 100))
    cat("   Next: Run og_odds.R to validate ATS performance\n\n")
  } else {
    cat("⚠️ MODEL NEEDS IMPROVEMENT\n")
    cat(sprintf("   %.1f%% hit rate - below target\n", overall_metrics$hit_rate * 100))
    cat("   Review feature engineering and calibration\n\n")
  }
}

cat("════════════════════════════════════════════════════════════════\n\n")