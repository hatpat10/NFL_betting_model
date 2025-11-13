# ============================================================================
# NFL MODEL BACKTEST - ENHANCED PIPELINE VALIDATION (v3.0)
# ============================================================================
# Tests YOUR EPA-based predictions against actual game results
# NOW INCLUDES: Weather adjustments, injury data, enhanced features
# UPDATED: Works with CSV outputs from enhanced pipeline
# 
# Run AFTER generating predictions for multiple weeks using:
#   nfl_master_pipeline_enhanced.R
#
# This backtest validates:
#   - Winner prediction accuracy (hit rate)
#   - Margin prediction accuracy (MAE, RMSE, bias)
#   - Spread betting profitability (ROI)
#   - Enhanced vs Standard model comparison
#   - Confidence level analysis
# ============================================================================

library(dplyr)
library(tidyr)
library(nflreadr)
library(ggplot2)
library(writexl)

# ============================================================================
# CONFIGURATION
# ============================================================================

BASE_DIR <- "C:\\Users\\Patsc\\Documents\\NFL_betting_model"
BACKTEST_WEEKS <- 5:10  # Weeks to test (must have been predicted already)
SEASON <- 2025
BET_SIZE <- 100  # $100 per bet for simulation

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║  BACKTEST - ENHANCED PIPELINE VALIDATION (v3.0)               ║\n")
cat("║  Testing Weeks:", paste(BACKTEST_WEEKS, collapse = ", "), "                                              ║\n")
cat("║  With weather, injury, & rest adjustments                     ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

# Create backtest directory
backtest_dir <- file.path(BASE_DIR, "backtest_results")
dir.create(backtest_dir, showWarnings = FALSE, recursive = TRUE)

# ============================================================================
# STEP 1: LOAD ACTUAL GAME RESULTS
# ============================================================================

cat("[1/6] Loading actual game results...\n")

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

cat("  ✓ Loaded", nrow(actuals), "completed games\n\n")

# ============================================================================
# STEP 2: LOAD PREDICTIONS FROM ENHANCED PIPELINE
# ============================================================================

cat("[2/6] Loading predictions from enhanced pipeline...\n")

load_week_predictions <- function(week_num, type = "enhanced") {
  
  week_dir <- file.path(BASE_DIR, paste0('week', week_num), 'matchup_analysis')
  
  if (type == "enhanced") {
    pred_file <- file.path(week_dir, "betting_recommendations_enhanced.csv")
  } else {
    pred_file <- file.path(week_dir, "betting_recommendations.csv")
  }
  
  if (!file.exists(pred_file)) {
    return(NULL)
  }
  
  tryCatch({
    preds <- read.csv(pred_file, stringsAsFactors = FALSE) %>%
      mutate(
        week = week_num,
        prediction_type = type
      ) %>%
      as_tibble()
    
    return(preds)
  }, error = function(e) {
    cat("  ⚠️ Error reading Week", week_num, type, "predictions:", e$message, "\n")
    return(NULL)
  })
}

# Load enhanced predictions
enhanced_predictions <- list()
standard_predictions <- list()
missing_weeks <- c()

for (week_num in BACKTEST_WEEKS) {
  
  # Try enhanced first
  enhanced <- load_week_predictions(week_num, "enhanced")
  if (!is.null(enhanced)) {
    enhanced_predictions[[length(enhanced_predictions) + 1]] <- enhanced
    cat("  ✓ Week", week_num, "- ENHANCED predictions loaded (", nrow(enhanced), "games)\n")
  }
  
  # Try standard as backup
  standard <- load_week_predictions(week_num, "standard")
  if (!is.null(standard)) {
    standard_predictions[[length(standard_predictions) + 1]] <- standard
    cat("  ✓ Week", week_num, "- STANDARD predictions loaded (", nrow(standard), "games)\n")
  }
  
  if (is.null(enhanced) && is.null(standard)) {
    cat("  ❌ Week", week_num, "predictions not found\n")
    missing_weeks <- c(missing_weeks, week_num)
  }
}

if (length(missing_weeks) > 0) {
  cat("\n⚠️ MISSING PREDICTIONS FOR WEEKS:", paste(missing_weeks, collapse = ", "), "\n")
  cat("   Run the enhanced pipeline for these weeks first!\n\n")
}

# Combine predictions
predictions_list <- list()

if (length(enhanced_predictions) > 0) {
  predictions_list$enhanced <- bind_rows(enhanced_predictions)
  cat("\n  ✓ Enhanced predictions:", nrow(predictions_list$enhanced), "total\n")
}

if (length(standard_predictions) > 0) {
  predictions_list$standard <- bind_rows(standard_predictions)
  cat("  ✓ Standard predictions:", nrow(predictions_list$standard), "total\n")
}

if (length(predictions_list) == 0) {
  stop("\n❌ No predictions found! Generate predictions first.\n")
}

cat("\n")

# ============================================================================
# STEP 3: STANDARDIZE AND JOIN WITH ACTUALS
# ============================================================================

cat("[3/6] Matching predictions to actual results...\n")

analyze_predictions <- function(preds, actuals_df, pred_type) {
  
  # Standardize column names (handle variations)
  preds_clean <- preds %>%
    rename_with(tolower) %>%
    mutate(
      matchup_key = if("game" %in% names(.)) game else paste(away_team, "at", home_team)
    )
  
  # Join with actuals
  comparison <- preds_clean %>%
    left_join(
      actuals_df %>% select(week, matchup_key, actual_home_score, actual_away_score,
                            actual_margin, actual_winner, actual_total, home_won),
      by = c("week", "matchup_key")
    ) %>%
    filter(!is.na(actual_margin))  # Only keep games that were played
  
  if (nrow(comparison) == 0) {
    cat("  ❌ Could not match", pred_type, "predictions to actuals\n")
    return(NULL)
  }
  
  # Calculate accuracy metrics
  comparison <- comparison %>%
    mutate(
      # Winner prediction
      predicted_winner = if_else(projected_margin > 0, home_team, away_team),
      correct_winner = predicted_winner == actual_winner,
      
      # Margin accuracy  
      margin_error = abs(projected_margin - actual_margin),
      squared_error = margin_error^2,
      prediction_bias = projected_margin - actual_margin,
      
      # Absolute margin
      abs_projected = abs(projected_margin),
      abs_actual = abs(actual_margin),
      
      # Game categories
      close_game = abs_actual < 7,
      blowout = abs_actual >= 14,
      projected_close = abs_projected < 7,
      
      # Confidence-based accuracy (if available)
      has_confidence = "confidence" %in% names(.)
    )
  
  cat("  ✓ Matched", nrow(comparison), pred_type, "predictions\n")
  
  return(comparison)
}

results <- list()

for (pred_type in names(predictions_list)) {
  results[[pred_type]] <- analyze_predictions(
    predictions_list[[pred_type]], 
    actuals, 
    pred_type
  )
}

cat("\n")

# ============================================================================
# STEP 4: CALCULATE PERFORMANCE METRICS
# ============================================================================

cat("[4/6] Calculating performance metrics...\n")

calculate_metrics <- function(comparison_df, model_name) {
  
  if (is.null(comparison_df) || nrow(comparison_df) == 0) {
    return(NULL)
  }
  
  # Overall metrics
  overall <- comparison_df %>%
    summarise(
      model = model_name,
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
      blowout_hit_rate = mean(correct_winner[blowout], na.rm = TRUE)
    )
  
  # By week
  by_week <- comparison_df %>%
    group_by(week) %>%
    summarise(
      model = model_name,
      games = n(),
      hit_rate = mean(correct_winner, na.rm = TRUE),
      mae = mean(margin_error, na.rm = TRUE),
      .groups = 'drop'
    )
  
  # By confidence (if available)
  by_confidence <- NULL
  if ("confidence" %in% names(comparison_df)) {
    by_confidence <- comparison_df %>%
      filter(!is.na(confidence)) %>%
      group_by(confidence) %>%
      summarise(
        model = model_name,
        games = n(),
        hit_rate = mean(correct_winner, na.rm = TRUE),
        mae = mean(margin_error, na.rm = TRUE),
        .groups = 'drop'
      )
  }
  
  return(list(
    overall = overall,
    by_week = by_week,
    by_confidence = by_confidence,
    comparison = comparison_df
  ))
}

metrics <- list()
for (pred_type in names(results)) {
  if (!is.null(results[[pred_type]])) {
    metrics[[pred_type]] <- calculate_metrics(results[[pred_type]], toupper(pred_type))
  }
}

cat("  ✓ Metrics calculated for", length(metrics), "model(s)\n\n")

# ============================================================================
# STEP 5: CALCULATE PROFITABILITY
# ============================================================================

cat("[5/6] Calculating profitability...\n")

calculate_profit <- function(hit_rate, num_bets, bet_size = 100) {
  if (is.na(hit_rate) || num_bets == 0) {
    return(list(profit = 0, roi = 0, units = 0))
  }
  
  wins <- hit_rate * num_bets
  losses <- (1 - hit_rate) * num_bets
  
  # At -110 odds: win $100 for every $110 risked
  profit <- (wins * (bet_size * 100/110)) - (losses * bet_size)
  roi <- (profit / (num_bets * bet_size)) * 100
  units <- profit / bet_size
  
  return(list(profit = profit, roi = roi, units = units))
}

profitability <- list()

for (pred_type in names(metrics)) {
  if (!is.null(metrics[[pred_type]])) {
    overall <- metrics[[pred_type]]$overall
    
    prof <- calculate_profit(
      overall$hit_rate,
      overall$total_games,
      BET_SIZE
    )
    
    profitability[[pred_type]] <- tibble(
      model = pred_type,
      total_games = overall$total_games,
      hit_rate = overall$hit_rate,
      profit = prof$profit,
      roi = prof$roi,
      units = prof$units
    )
  }
}

profit_comparison <- bind_rows(profitability)

cat("  ✓ Profitability calculated\n\n")

# ============================================================================
# STEP 6: DISPLAY RESULTS
# ============================================================================

cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║  BACKTEST RESULTS - ENHANCED PIPELINE                         ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n\n")

for (pred_type in names(metrics)) {
  
  if (is.null(metrics[[pred_type]])) next
  
  overall <- metrics[[pred_type]]$overall
  by_week <- metrics[[pred_type]]$by_week
  by_conf <- metrics[[pred_type]]$by_confidence
  prof <- profitability[[pred_type]]
  
  cat("════════════════════════════════════════════════════════════════\n")
  cat(sprintf("  %s MODEL\n", toupper(pred_type)))
  cat("════════════════════════════════════════════════════════════════\n\n")
  
  cat("📊 OVERALL PERFORMANCE:\n")
  cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
  cat(sprintf("Total Games:         %d\n", overall$total_games))
  cat(sprintf("Correct Winners:     %d (%.1f%%)\n", 
              overall$correct_winners, 
              overall$hit_rate * 100))
  
  # Hit rate interpretation
  if (overall$hit_rate >= 0.60) {
    cat("  ✅ STRONG MODEL - Excellent performance!\n")
  } else if (overall$hit_rate >= 0.55) {
    cat("  ✅ GOOD MODEL - Solid edge\n")
  } else if (overall$hit_rate >= 0.524) {
    cat("  ⚠️ MARGINAL - Barely profitable\n")
  } else {
    cat("  ❌ UNPROFITABLE - Do not bet!\n")
  }
  
  cat(sprintf("\nMean Abs Error:      %.2f points", overall$mean_abs_error))
  if (overall$mean_abs_error < 10) {
    cat(" ✅\n")
  } else {
    cat(" ⚠️\n")
  }
  
  cat(sprintf("RMSE:                %.2f points\n", overall$rmse))
  cat(sprintf("Median Error:        %.2f points\n", overall$median_error))
  cat(sprintf("Bias:                %+.2f points ", overall$bias))
  
  if (abs(overall$bias) < 1) {
    cat("✅ (No systematic bias)\n")
  } else if (overall$bias > 0) {
    cat("⚠️ (Over-predicting home teams)\n")
  } else {
    cat("⚠️ (Under-predicting home teams)\n")
  }
  
  # Game type performance
  cat("\n📈 BY GAME TYPE:\n")
  cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
  cat(sprintf("Close Games (<7 pts): %d games, %.1f%% accuracy\n",
              overall$close_games, overall$close_hit_rate * 100))
  cat(sprintf("Blowouts (≥14 pts):   %d games, %.1f%% accuracy\n",
              overall$blowout_games, overall$blowout_hit_rate * 100))
  
  # Profitability
  cat("\n💰 PROFITABILITY ANALYSIS:\n")
  cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
  cat(sprintf("Bet Size:            $%d per game\n", BET_SIZE))
  cat(sprintf("Total Risked:        $%d\n", prof$total_games * BET_SIZE))
  cat(sprintf("Hit Rate:            %.1f%% (need 52.4%% to break even)\n", prof$hit_rate * 100))
  cat(sprintf("Profit/Loss:         $%+.2f\n", prof$profit))
  cat(sprintf("ROI:                 %+.1f%%\n", prof$roi))
  cat(sprintf("Units Won/Lost:      %+.2f units\n", prof$units))
  
  if (prof$profit > 0) {
    cat("  ✅ PROFITABLE\n")
  } else {
    cat("  ❌ LOSING\n")
  }
  
  # By week
  cat("\n📅 PERFORMANCE BY WEEK:\n")
  cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
  by_week_display <- by_week %>%
    mutate(
      hit_rate_pct = sprintf("%.1f%%", hit_rate * 100),
      mae_display = sprintf("%.2f", mae)
    ) %>%
    select(Week = week, Games = games, `Hit Rate` = hit_rate_pct, MAE = mae_display)
  
  print(by_week_display, row.names = FALSE)
  
  # By confidence (if available)
  if (!is.null(by_conf) && nrow(by_conf) > 0) {
    cat("\n🎯 PERFORMANCE BY CONFIDENCE LEVEL:\n")
    cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    by_conf_display <- by_conf %>%
      mutate(
        hit_rate_pct = sprintf("%.1f%%", hit_rate * 100),
        mae_display = sprintf("%.2f", mae)
      ) %>%
      select(Confidence = confidence, Games = games, 
             `Hit Rate` = hit_rate_pct, MAE = mae_display)
    
    print(by_conf_display, row.names = FALSE)
  }
  
  cat("\n")
}

# ============================================================================
# MODEL COMPARISON (if both exist)
# ============================================================================

if (length(metrics) > 1) {
  cat("════════════════════════════════════════════════════════════════\n")
  cat("  ENHANCED vs STANDARD COMPARISON\n")
  cat("════════════════════════════════════════════════════════════════\n\n")
  
  comparison_table <- bind_rows(
    lapply(names(metrics), function(x) {
      metrics[[x]]$overall %>%
        mutate(model = toupper(x))
    })
  ) %>%
    select(Model = model, Games = total_games, `Hit Rate` = hit_rate, 
           MAE = mean_abs_error, RMSE = rmse, Bias = bias)
  
  print(comparison_table, row.names = FALSE)
  
  cat("\n💰 PROFIT COMPARISON:\n")
  prof_table <- profit_comparison %>%
    mutate(
      model = toupper(model),
      hit_rate_pct = sprintf("%.1f%%", hit_rate * 100),
      profit_display = sprintf("$%+.2f", profit),
      roi_display = sprintf("%+.1f%%", roi)
    ) %>%
    select(Model = model, Games = total_games, `Hit Rate` = hit_rate_pct,
           Profit = profit_display, ROI = roi_display, Units = units)
  
  print(prof_table, row.names = FALSE)
  
  # Calculate improvement
  if ("enhanced" %in% names(metrics) && "standard" %in% names(metrics)) {
    enh <- metrics$enhanced$overall
    std <- metrics$standard$overall
    
    hit_diff <- (enh$hit_rate - std$hit_rate) * 100
    mae_diff <- std$mean_abs_error - enh$mean_abs_error
    
    cat("\n📈 ENHANCEMENT IMPACT:\n")
    if (hit_diff > 0) {
      cat(sprintf("  ✅ Hit rate improved by %.1f percentage points\n", hit_diff))
    } else {
      cat(sprintf("  ❌ Hit rate declined by %.1f percentage points\n", abs(hit_diff)))
    }
    
    if (mae_diff > 0) {
      cat(sprintf("  ✅ MAE improved by %.2f points\n", mae_diff))
    } else {
      cat(sprintf("  ❌ MAE got worse by %.2f points\n", abs(mae_diff)))
    }
    
    cat("\n")
  }
}

# ============================================================================
# BIGGEST ERRORS
# ============================================================================

cat("════════════════════════════════════════════════════════════════\n")
cat("🎯 BIGGEST PREDICTION ERRORS\n")
cat("════════════════════════════════════════════════════════════════\n\n")

for (pred_type in names(results)) {
  if (is.null(results[[pred_type]])) next
  
  cat(sprintf("--- %s MODEL ---\n", toupper(pred_type)))
  
  worst_misses <- results[[pred_type]] %>%
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
  cat("\n")
}

# ============================================================================
# SAVE DETAILED RESULTS
# ============================================================================

cat("════════════════════════════════════════════════════════════════\n")
cat("💾 Saving detailed results...\n")
cat("════════════════════════════════════════════════════════════════\n\n")

# Create Excel workbook with multiple sheets
output_sheets <- list()

# Summary sheet
summary_rows <- list()
for (pred_type in names(metrics)) {
  if (!is.null(metrics[[pred_type]])) {
    overall <- metrics[[pred_type]]$overall
    prof <- profitability[[pred_type]]
    
    summary_rows[[pred_type]] <- tibble(
      Model = toupper(pred_type),
      Total_Games = overall$total_games,
      Hit_Rate = sprintf("%.1f%%", overall$hit_rate * 100),
      Correct_Winners = overall$correct_winners,
      MAE = round(overall$mean_abs_error, 2),
      RMSE = round(overall$rmse, 2),
      Bias = round(overall$bias, 2),
      Profit = round(prof$profit, 2),
      ROI = sprintf("%.1f%%", prof$roi),
      Close_Game_Hit_Rate = sprintf("%.1f%%", overall$close_hit_rate * 100),
      Blowout_Hit_Rate = sprintf("%.1f%%", overall$blowout_hit_rate * 100)
    )
  }
}

output_sheets$Summary <- bind_rows(summary_rows)

# Add detailed results for each model
for (pred_type in names(results)) {
  if (!is.null(results[[pred_type]])) {
    output_sheets[[paste0(toupper(pred_type), "_Details")]] <- results[[pred_type]] %>%
      select(week, matchup_key, projected_margin, actual_margin, margin_error,
             correct_winner, predicted_winner, actual_winner, 
             any_of(c("confidence", "weather_impact", "is_thursday")))
  }
}

# Weekly performance
for (pred_type in names(metrics)) {
  if (!is.null(metrics[[pred_type]])) {
    output_sheets[[paste0(toupper(pred_type), "_By_Week")]] <- metrics[[pred_type]]$by_week
  }
}

# Write Excel file
write_xlsx(output_sheets, file.path(backtest_dir, "backtest_comprehensive_results.xlsx"))

cat("  ✓ Comprehensive Excel file saved\n")

# Save CSVs for easy access
for (pred_type in names(results)) {
  if (!is.null(results[[pred_type]])) {
    write.csv(
      results[[pred_type]],
      file.path(backtest_dir, paste0("backtest_", pred_type, "_detailed.csv")),
      row.names = FALSE
    )
  }
}

cat("  ✓ Individual CSV files saved\n")

# ============================================================================
# CREATE VISUALIZATIONS
# ============================================================================

cat("\n📊 Creating visualizations...\n")

# 1. Prediction accuracy scatter plot
for (pred_type in names(results)) {
  if (is.null(results[[pred_type]])) next
  
  data <- results[[pred_type]]
  overall <- metrics[[pred_type]]$overall
  
  accuracy_plot <- ggplot(data, aes(x = actual_margin, y = projected_margin)) +
    geom_point(aes(color = correct_winner), size = 3, alpha = 0.7) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "red", size = 1) +
    geom_hline(yintercept = 0, linetype = "dotted", alpha = 0.5) +
    geom_vline(xintercept = 0, linetype = "dotted", alpha = 0.5) +
    scale_color_manual(
      values = c("TRUE" = "#27ae60", "FALSE" = "#e74c3c"),
      labels = c("TRUE" = "Correct Winner", "FALSE" = "Wrong Winner")
    ) +
    labs(
      title = sprintf("%s Model - Prediction Accuracy", toupper(pred_type)),
      subtitle = sprintf("Hit Rate: %.1f%% | MAE: %.2f pts | RMSE: %.2f pts | Bias: %+.2f",
                         overall$hit_rate * 100,
                         overall$mean_abs_error,
                         overall$rmse,
                         overall$bias),
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
    file.path(backtest_dir, paste0("accuracy_scatter_", pred_type, ".png")),
    accuracy_plot,
    width = 10,
    height = 8,
    dpi = 300
  )
}

cat("  ✓ Scatter plots created\n")

# 2. Weekly performance comparison
if (length(metrics) > 0) {
  weekly_data <- bind_rows(lapply(names(metrics), function(x) {
    metrics[[x]]$by_week %>% mutate(model = toupper(x))
  }))
  
  weekly_plot <- ggplot(weekly_data, aes(x = as.factor(week), y = hit_rate, 
                                         group = model, color = model)) +
    geom_line(size = 1.2) +
    geom_point(size = 3) +
    geom_hline(yintercept = 0.524, linetype = "dashed", color = "red") +
    scale_y_continuous(labels = scales::percent) +
    scale_color_manual(values = c("ENHANCED" = "#3498db", "STANDARD" = "#95a5a6")) +
    labs(
      title = "Weekly Hit Rate Performance",
      subtitle = "Red line = Break-even threshold (52.4%)",
      x = "Week",
      y = "Hit Rate",
      color = "Model"
    ) +
    theme_minimal(base_size = 13) +
    theme(
      plot.title = element_text(face = "bold", hjust = 0.5),
      legend.position = "bottom"
    )
  
  ggsave(
    file.path(backtest_dir, "weekly_performance.png"),
    weekly_plot,
    width = 10,
    height = 6,
    dpi = 300
  )
  
  cat("  ✓ Weekly performance plot created\n")
}

# 3. Profitability comparison (if multiple models)
if (nrow(profit_comparison) > 1) {
  profit_plot <- ggplot(profit_comparison, aes(x = toupper(model), y = profit, fill = model)) +
    geom_col() +
    geom_hline(yintercept = 0, linetype = "dashed") +
    geom_text(aes(label = sprintf("$%.0f\n(%.1f%%)", profit, roi)), 
              vjust = -0.5, size = 4, fontface = "bold") +
    scale_fill_manual(values = c("enhanced" = "#27ae60", "standard" = "#95a5a6")) +
    labs(
      title = "Model Profitability Comparison",
      subtitle = sprintf("$%d per game at -110 odds", BET_SIZE),
      x = NULL,
      y = "Profit/Loss ($)"
    ) +
    theme_minimal(base_size = 13) +
    theme(
      plot.title = element_text(face = "bold", hjust = 0.5),
      legend.position = "none"
    )
  
  ggsave(
    file.path(backtest_dir, "profitability_comparison.png"),
    profit_plot,
    width = 8,
    height = 6,
    dpi = 300
  )
  
  cat("  ✓ Profitability comparison created\n")
}

cat("\n")

# ============================================================================
# FINAL SUMMARY
# ============================================================================

cat("════════════════════════════════════════════════════════════════\n")
cat("🎉 BACKTEST COMPLETE!\n")
cat("════════════════════════════════════════════════════════════════\n\n")

cat("📁 Results saved to:", backtest_dir, "\n\n")

cat("📄 FILES CREATED:\n")
cat("  • backtest_comprehensive_results.xlsx (all sheets)\n")
for (pred_type in names(results)) {
  cat(sprintf("  • backtest_%s_detailed.csv\n", pred_type))
  cat(sprintf("  • accuracy_scatter_%s.png\n", pred_type))
}
if (length(metrics) > 1) {
  cat("  • weekly_performance.png\n")
  cat("  • profitability_comparison.png\n")
}

cat("\n════════════════════════════════════════════════════════════════\n")
cat("RECOMMENDATIONS:\n")
cat("════════════════════════════════════════════════════════════════\n\n")

# Get best model
best_model <- profit_comparison %>%
  arrange(desc(hit_rate)) %>%
  slice(1)

if (best_model$hit_rate >= 0.60) {
  cat("✅ EXCELLENT MODEL PERFORMANCE\n")
  cat(sprintf("   %s model shows %.1f%% hit rate\n", toupper(best_model$model), best_model$hit_rate * 100))
  cat("   Next steps:\n")
  cat("   1. Continue tracking for 2-3 more weeks\n")
  cat("   2. Paper trade to validate\n")
  cat("   3. Define strict bankroll management (2-5% per bet)\n")
  cat("   4. Consider graduated real money testing\n\n")
  
} else if (best_model$hit_rate >= 0.55) {
  cat("✅ GOOD MODEL - EDGE CONFIRMED\n")
  cat(sprintf("   %s model shows %.1f%% hit rate\n", toupper(best_model$model), best_model$hit_rate * 100))
  cat("   Next steps:\n")
  cat("   1. Backtest 3-4 more weeks for confirmation\n")
  cat("   2. Paper trade for validation\n")
  cat("   3. Analyze close games vs blowouts\n")
  cat("   4. Consider selective betting on high-confidence picks\n\n")
  
} else if (best_model$hit_rate >= 0.524) {
  cat("⚠️ MARGINAL EDGE - NEED MORE DATA\n")
  cat(sprintf("   %s model shows %.1f%% hit rate\n", toupper(best_model$model), best_model$hit_rate * 100))
  cat("   Recommendations:\n")
  cat("   1. Backtest full season when complete\n")
  cat("   2. Increase sample size before betting\n")
  cat("   3. Analyze by confidence levels\n")
  cat("   4. Consider focusing on specific game types\n")
  cat("   5. DO NOT bet with real money yet\n\n")
  
} else {
  cat("❌ MODEL NEEDS IMPROVEMENT\n")
  cat(sprintf("   %s model shows %.1f%% hit rate (below break-even)\n", 
              toupper(best_model$model), best_model$hit_rate * 100))
  cat("   Critical actions:\n")
  cat("   1. Analyze systematic biases\n")
  cat("   2. Review feature weights\n")
  cat("   3. Check if enhanced adjustments helping or hurting\n")
  cat("   4. Consider alternative methodologies\n")
  cat("   5. DO NOT bet real money\n\n")
}

# Enhanced model specific feedback
if ("enhanced" %in% names(metrics) && "standard" %in% names(metrics)) {
  enh_rate <- metrics$enhanced$overall$hit_rate
  std_rate <- metrics$standard$overall$hit_rate
  
  if (enh_rate > std_rate) {
    cat("✨ ENHANCED FEATURES WORKING!\n")
    cat(sprintf("   Weather/injury/rest adjustments improved performance by %.1f%%\n",
                (enh_rate - std_rate) * 100))
  } else {
    cat("⚠️ ENHANCED FEATURES NOT HELPING\n")
    cat("   Standard model performing better - review adjustment logic\n")
  }
}

cat("\n════════════════════════════════════════════════════════════════\n\n")