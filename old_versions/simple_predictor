# ============================================================================
# 2025 NFL GAME PREDICTOR - SIMPLIFIED & FOCUSED
# ============================================================================
# Trains on 2024 season â†’ Predicts upcoming 2025 games
# Uses: Random Forest, Gradient Boosting, Ridge Regression, Monte Carlo
# ============================================================================

library(tidyverse)
library(nflreadr)
library(nflfastR)
library(nflplotR)
library(nfl4th)
library(nflseedR)
library(randomForest)
library(gbm)
library(glmnet)
library(lubridate)
library(zoo)

set.seed(42)

results_dir <- "nfl_2025_predictions"
dir.create(results_dir, showWarnings = FALSE)

cat("ðŸˆ 2025 NFL GAME PREDICTOR\n")
cat(paste(rep("=", 70), collapse = ""), "\n\n")

# ============================================================================
# STEP 1: LOAD DATA
# ============================================================================

cat("ðŸ“Š Loading NFL data...\n")

# Load 2024 for training
schedules_2024 <- load_schedules(seasons = 2024) %>%
  filter(game_type == "REG", !is.na(result))

pbp_2024 <- load_pbp(seasons = 2024)

# Load 2025 for predictions
schedules_2025 <- load_schedules(seasons = 2025) %>%
  filter(game_type == "REG")

pbp_2025 <- load_pbp(seasons = 2025)

cat(sprintf("âœ“ 2024 Training: %d completed games\n", nrow(schedules_2024)))
cat(sprintf("âœ“ 2025 Season: %d total games\n", nrow(schedules_2025)))

# Identify upcoming games - ONLY WEEK 8
current_date <- Sys.Date()

upcoming_games <- schedules_2025 %>%
  filter(week == 8) %>%  # ONLY WEEK 8
  filter(is.na(result)) %>%  # No result yet
  mutate(game_date = as.Date(gameday)) %>%
  select(game_id, week, season, gameday, weekday, gametime, 
         home_team, away_team, spread_line, total_line, home_rest, away_rest)

completed_2025 <- schedules_2025 %>%
  filter(!is.na(result))

cat(sprintf("âœ“ 2025 Completed: %d games\n", nrow(completed_2025)))
cat(sprintf("ðŸŽ¯ WEEK 8 GAMES TO PREDICT: %d games\n", nrow(upcoming_games)))

if (nrow(upcoming_games) > 0) {
  cat(sprintf("  Game dates: %s to %s\n\n", 
              min(upcoming_games$gameday), max(upcoming_games$gameday)))
} else {
  cat("\nâš ï¸  Week 8 games not found or already completed.\n\n")
}

if (nrow(upcoming_games) == 0) {
  cat("âš ï¸  No upcoming games to predict.\n\n")
  cat("The 2025 regular season appears to be complete!\n")
  cat("To predict playoff games, you'll need playoff schedules.\n\n")
  
  # Show last few completed games instead
  cat("ðŸ“Š LATEST COMPLETED 2025 GAMES:\n")
  cat(paste(rep("-", 70), collapse = ""), "\n")
  
  recent_games <- completed_2025 %>%
    arrange(desc(gameday)) %>%
    head(10) %>%
    select(week, gameday, away_team, home_team, away_score, home_score, spread_line)
  
  print(recent_games)
  
  cat("\n\nTo use this model:\n")
  cat("1. Wait for playoff schedule to be released\n")
  cat("2. Or use it early next season (2026)\n")
  cat("3. Or modify to backtest 2025 completed games\n\n")
  
  quit(save = "no")
}

# ============================================================================
# STEP 2: FEATURE ENGINEERING
# ============================================================================

cat("ðŸ”§ Building features...\n")

# Function to calculate team stats
calculate_team_stats <- function(pbp_data, schedules_data) {
  
  # Offensive stats
  offense <- pbp_data %>%
    filter(!is.na(posteam), !is.na(yards_gained)) %>%
    group_by(game_id, posteam) %>%
    summarise(
      total_yards = sum(yards_gained, na.rm = TRUE),
      passing_yards = sum(yards_gained[pass == 1], na.rm = TRUE),
      rushing_yards = sum(yards_gained[rush == 1], na.rm = TRUE),
      yards_per_play = mean(yards_gained, na.rm = TRUE),
      turnovers = sum(interception == 1 | fumble_lost == 1, na.rm = TRUE),
      third_down_conv = sum(third_down_converted == 1, na.rm = TRUE),
      third_down_att = sum(third_down_converted == 1 | third_down_failed == 1, na.rm = TRUE),
      explosive_plays = sum(yards_gained >= 20, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(third_down_pct = ifelse(third_down_att > 0, third_down_conv / third_down_att, 0))
  
  # Defensive stats
  defense <- pbp_data %>%
    filter(!is.na(defteam), !is.na(yards_gained)) %>%
    group_by(game_id, defteam) %>%
    summarise(
      yards_allowed = sum(yards_gained, na.rm = TRUE),
      turnovers_forced = sum(interception == 1 | fumble_lost == 1, na.rm = TRUE),
      .groups = "drop"
    )
  
  # Merge with schedules
  stats <- schedules_data %>%
    left_join(offense, by = c("game_id", "home_team" = "posteam")) %>%
    left_join(defense, by = c("game_id", "home_team" = "defteam")) %>%
    rename_with(~paste0("home_", .), .cols = total_yards:turnovers_forced) %>%
    left_join(offense, by = c("game_id", "away_team" = "posteam")) %>%
    left_join(defense, by = c("game_id", "away_team" = "defteam")) %>%
    rename_with(~paste0("away_", .), .cols = total_yards:turnovers_forced)
  
  return(stats)
}

# Calculate stats for 2024 and completed 2025 games
cat("  Processing 2024 data...\n")
stats_2024 <- calculate_team_stats(pbp_2024, schedules_2024)

if (nrow(completed_2025) > 0) {
  cat("  Processing 2025 data...\n")
  stats_2025 <- calculate_team_stats(pbp_2025, completed_2025)
  all_stats <- bind_rows(stats_2024, stats_2025)
} else {
  all_stats <- stats_2024
}

# Calculate rolling averages
cat("  Calculating rolling averages...\n")

calculate_rolling <- function(data) {
  all_teams <- unique(c(data$home_team, data$away_team))
  rolling_list <- list()
  
  for (team in all_teams) {
    team_games <- data %>%
      filter(home_team == team | away_team == team) %>%
      arrange(season, week) %>%
      mutate(
        is_home = (home_team == team),
        pts_scored = ifelse(is_home, home_score, away_score),
        pts_allowed = ifelse(is_home, away_score, home_score),
        yards = ifelse(is_home, home_total_yards, away_total_yards),
        yards_allowed = ifelse(is_home, home_yards_allowed, away_yards_allowed),
        won = ifelse(is_home, home_score > away_score, away_score > home_score)
      ) %>%
      mutate(
        roll3_pts_scored = lag(zoo::rollmean(pts_scored, k = 3, fill = NA, align = "right")),
        roll3_pts_allowed = lag(zoo::rollmean(pts_allowed, k = 3, fill = NA, align = "right")),
        roll3_yards = lag(zoo::rollmean(yards, k = 3, fill = NA, align = "right")),
        roll3_yards_allowed = lag(zoo::rollmean(yards_allowed, k = 3, fill = NA, align = "right")),
        roll3_win_pct = lag(zoo::rollmean(as.numeric(won), k = 3, fill = NA, align = "right")),
        season_avg_scored = lag(cummean(pts_scored)),
        season_avg_allowed = lag(cummean(pts_allowed))
      ) %>%
      mutate(team = team) %>%
      select(game_id, season, week, team, starts_with("roll"), starts_with("season"))
    
    rolling_list[[team]] <- team_games
  }
  
  return(bind_rows(rolling_list))
}

rolling <- calculate_rolling(all_stats)

# Merge rolling features
cat("  Merging features...\n")

model_data <- all_stats %>%
  left_join(
    rolling %>% 
      rename_with(~paste0("home_", .), .cols = (starts_with("roll") | starts_with("season")) & !matches("^(game_id|season|week|team)$")),
    by = c("game_id", "season", "week", "home_team" = "team")
  ) %>%
  left_join(
    rolling %>% 
      rename_with(~paste0("away_", .), .cols = (starts_with("roll") | starts_with("season")) & !matches("^(game_id|season|week|team)$")),
    by = c("game_id", "season", "week", "away_team" = "team")
  ) %>%
  mutate(
    rest_advantage = home_rest - away_rest,
    pts_diff = (home_roll3_pts_scored - home_roll3_pts_allowed) - 
      (away_roll3_pts_scored - away_roll3_pts_allowed),
    home_off_vs_away_def = home_roll3_pts_scored - away_roll3_pts_allowed,
    away_off_vs_home_def = away_roll3_pts_scored - home_roll3_pts_allowed,
    home_field_advantage = 2.5
  )

cat(sprintf("âœ“ Created %d features\n\n", ncol(model_data)))

# ============================================================================
# STEP 3: PREPARE TRAINING DATA (ALL 2024 GAMES)
# ============================================================================

cat("ðŸŽ“ Preparing training data...\n")

train_data <- model_data %>%
  filter(season == 2024, !is.na(home_roll3_pts_scored), !is.na(away_roll3_pts_scored))

feature_cols <- c(
  "home_roll3_pts_scored", "home_roll3_pts_allowed", "home_roll3_yards", 
  "home_roll3_yards_allowed", "home_roll3_win_pct",
  "away_roll3_pts_scored", "away_roll3_pts_allowed", "away_roll3_yards",
  "away_roll3_yards_allowed", "away_roll3_win_pct",
  "home_season_avg_scored", "home_season_avg_allowed",
  "away_season_avg_scored", "away_season_avg_allowed",
  "rest_advantage", "pts_diff", "home_off_vs_away_def", 
  "away_off_vs_home_def", "home_field_advantage"
)

X_train <- train_data[, feature_cols]
y_home_train <- train_data$home_score
y_away_train <- train_data$away_score

# Remove NAs
complete_cases <- complete.cases(X_train)
X_train <- X_train[complete_cases, ]
y_home_train <- y_home_train[complete_cases]
y_away_train <- y_away_train[complete_cases]

cat(sprintf("âœ“ Training set: %d games with %d features\n\n", nrow(X_train), ncol(X_train)))

# ============================================================================
# STEP 4: TRAIN ENSEMBLE MODELS
# ============================================================================

cat("ðŸ¤– Training ensemble models on 2024 data...\n")

# Random Forest
cat("  Training Random Forest...\n")
rf_home <- randomForest(x = X_train, y = y_home_train, ntree = 200, mtry = 6)
rf_away <- randomForest(x = X_train, y = y_away_train, ntree = 200, mtry = 6)

# Gradient Boosting
cat("  Training Gradient Boosting...\n")
tryCatch({
  gbm_home <- gbm(home_score ~ ., 
                  data = cbind(X_train, home_score = y_home_train),
                  distribution = "gaussian",
                  n.trees = 200,
                  interaction.depth = 4,
                  shrinkage = 0.05,
                  bag.fraction = 0.5,
                  n.minobsinnode = 5,
                  verbose = FALSE)
  
  gbm_away <- gbm(away_score ~ .,
                  data = cbind(X_train, away_score = y_away_train),
                  distribution = "gaussian",
                  n.trees = 200,
                  interaction.depth = 4,
                  shrinkage = 0.05,
                  bag.fraction = 0.5,
                  n.minobsinnode = 5,
                  verbose = FALSE)
  use_gbm <- TRUE
}, error = function(e) {
  cat("  GBM failed, will use RF predictions\n")
  use_gbm <<- FALSE
})

# Ridge Regression
cat("  Training Ridge Regression...\n")
ridge_home <- cv.glmnet(as.matrix(X_train), y_home_train, alpha = 0)
ridge_away <- cv.glmnet(as.matrix(X_train), y_away_train, alpha = 0)

cat("âœ“ All models trained!\n\n")

# ============================================================================
# STEP 5: PREPARE 2025 DATA FOR PREDICTION
# ============================================================================

cat("ðŸ”® Preparing 2025 games for prediction...\n")

# Need to get rolling stats for upcoming games
# Use most recent completed games to calculate current team form

# Get the most recent week with data
if (nrow(completed_2025) > 0) {
  latest_week <- max(completed_2025$week)
  cat(sprintf("  Using data through Week %d of 2025\n", latest_week))
  
  # Combine 2024 and completed 2025 for rolling calculations
  combined_for_rolling <- bind_rows(stats_2024, stats_2025)
  rolling_current <- calculate_rolling(combined_for_rolling)
} else {
  cat("  Using end of 2024 season data (2025 hasn't started)\n")
  rolling_current <- calculate_rolling(stats_2024)
}

# For each upcoming game, get the latest rolling stats
upcoming_with_features <- upcoming_games %>%
  left_join(
    rolling_current %>% 
      group_by(team) %>%
      arrange(desc(season), desc(week)) %>%
      slice(1) %>%
      ungroup() %>%
      rename_with(~paste0("home_", .), .cols = starts_with("roll") | starts_with("season")),
    by = c("home_team" = "team")
  ) %>%
  left_join(
    rolling_current %>%
      group_by(team) %>%
      arrange(desc(season), desc(week)) %>%
      slice(1) %>%
      ungroup() %>%
      rename_with(~paste0("away_", .), .cols = starts_with("roll") | starts_with("season")),
    by = c("away_team" = "team")
  ) %>%
  mutate(
    rest_advantage = home_rest - away_rest,
    pts_diff = (home_roll3_pts_scored - home_roll3_pts_allowed) - 
      (away_roll3_pts_scored - away_roll3_pts_allowed),
    home_off_vs_away_def = home_roll3_pts_scored - away_roll3_pts_allowed,
    away_off_vs_home_def = away_roll3_pts_scored - home_roll3_pts_allowed,
    home_field_advantage = 2.5
  )

# Extract features for prediction
X_predict <- upcoming_with_features[, feature_cols]

# Impute any NAs with training means
for (col in names(X_predict)) {
  if (any(is.na(X_predict[[col]]))) {
    train_mean <- mean(X_train[[col]], na.rm = TRUE)
    X_predict[[col]][is.na(X_predict[[col]])] <- train_mean
    cat(sprintf("  Imputed NAs in %s with training mean\n", col))
  }
}

cat(sprintf("âœ“ Prepared %d upcoming games for prediction\n\n", nrow(X_predict)))

# ============================================================================
# STEP 6: MAKE PREDICTIONS FOR UPCOMING GAMES
# ============================================================================

cat("ðŸ“Š Generating predictions for upcoming 2025 games...\n")

# Get predictions from each model
pred_home_rf <- predict(rf_home, X_predict)
pred_away_rf <- predict(rf_away, X_predict)

if (use_gbm) {
  pred_home_gbm <- predict(gbm_home, X_predict, n.trees = 200)
  pred_away_gbm <- predict(gbm_away, X_predict, n.trees = 200)
} else {
  pred_home_gbm <- pred_home_rf
  pred_away_gbm <- pred_away_rf
}

pred_home_ridge <- predict(ridge_home, as.matrix(X_predict), s = "lambda.min")[,1]
pred_away_ridge <- predict(ridge_away, as.matrix(X_predict), s = "lambda.min")[,1]

# Ensemble (weighted average)
weights <- c(rf = 0.4, gbm = 0.35, ridge = 0.25)

pred_home <- weights['rf'] * pred_home_rf + 
  weights['gbm'] * pred_home_gbm +
  weights['ridge'] * pred_home_ridge

pred_away <- weights['rf'] * pred_away_rf +
  weights['gbm'] * pred_away_gbm +
  weights['ridge'] * pred_away_ridge

# Calculate uncertainty (SD across models)
pred_home_sd <- apply(cbind(pred_home_rf, pred_home_gbm, pred_home_ridge), 1, sd)
pred_away_sd <- apply(cbind(pred_away_rf, pred_away_gbm, pred_away_ridge), 1, sd)

cat("âœ“ Predictions generated\n\n")

# ============================================================================
# STEP 7: MONTE CARLO SIMULATION
# ============================================================================

cat("ðŸŽ² Running Monte Carlo simulations (1000 per game)...\n")

n_sims <- 1000
mc_results <- data.frame(
  win_prob = numeric(nrow(X_predict)),
  cover_prob = numeric(nrow(X_predict)),
  uncertainty = numeric(nrow(X_predict))
)

for (i in 1:nrow(X_predict)) {
  sim_home <- rnorm(n_sims, pred_home[i], pred_home_sd[i] + 7)
  sim_away <- rnorm(n_sims, pred_away[i], pred_away_sd[i] + 7)
  
  mc_results$win_prob[i] <- mean(sim_home > sim_away)
  
  if (!is.na(upcoming_with_features$spread_line[i])) {
    mc_results$cover_prob[i] <- mean((sim_home - sim_away) > upcoming_with_features$spread_line[i])
  } else {
    mc_results$cover_prob[i] <- NA
  }
  
  mc_results$uncertainty[i] <- sd(sim_home - sim_away)
}

cat("âœ“ Monte Carlo complete\n\n")

# ============================================================================
# STEP 8: CREATE PREDICTIONS DATAFRAME
# ============================================================================

predictions <- upcoming_with_features %>%
  mutate(
    predicted_home_score = round(pred_home, 1),
    predicted_away_score = round(pred_away, 1),
    predicted_margin = round(pred_home - pred_away, 1),
    predicted_total = round(pred_home + pred_away, 1),
    predicted_winner = ifelse(pred_home > pred_away, home_team, away_team),
    
    home_win_probability = mc_results$win_prob,
    spread_cover_probability = mc_results$cover_prob,
    prediction_uncertainty = mc_results$uncertainty,
    
    model_agreement = 1 / (1 + (pred_home_sd + pred_away_sd) / 2),
    
    # Confidence scores
    ml_confidence = (abs(home_win_probability - 0.5) * 2) * model_agreement,
    spread_confidence = ifelse(!is.na(spread_cover_probability),
                               abs(spread_cover_probability - 0.5) * 2 * model_agreement,
                               NA)
  )

# ============================================================================
# STEP 9: GENERATE BET RECOMMENDATIONS
# ============================================================================

cat("ðŸ’° Generating bet recommendations...\n\n")

# Thresholds
ML_PROB_THRESHOLD <- 0.58
ML_AGREEMENT_THRESHOLD <- 0.65
SPREAD_PROB_THRESHOLD <- 0.56
MIN_EDGE <- 3.5

recommendations <- list()

for (i in 1:nrow(predictions)) {
  game <- predictions[i, ]
  
  # Moneyline recommendations
  if (game$home_win_probability >= ML_PROB_THRESHOLD &&
      game$model_agreement >= ML_AGREEMENT_THRESHOLD) {
    
    rec <- tibble(
      week = game$week,
      gameday = game$gameday,
      matchup = paste(game$away_team, "@", game$home_team),
      bet_type = "MONEYLINE",
      recommendation = game$predicted_winner,
      predicted_score = paste0(game$predicted_home_score, "-", game$predicted_away_score),
      win_probability = sprintf("%.1f%%", game$home_win_probability * 100),
      confidence = sprintf("%.3f", game$ml_confidence),
      spread_line = game$spread_line
    )
    
    recommendations[[length(recommendations) + 1]] <- rec
  }
  
  # Spread recommendations
  if (!is.na(game$spread_line) &&
      !is.na(game$spread_cover_probability) &&
      game$spread_cover_probability >= SPREAD_PROB_THRESHOLD &&
      abs(game$predicted_margin - game$spread_line) >= MIN_EDGE) {
    
    home_covers <- game$predicted_margin > game$spread_line
    spread_pick <- ifelse(home_covers,
                          paste0(game$home_team, " ", game$spread_line),
                          paste0(game$away_team, " +", abs(game$spread_line)))
    
    rec <- tibble(
      week = game$week,
      gameday = game$gameday,
      matchup = paste(game$away_team, "@", game$home_team),
      bet_type = "SPREAD",
      recommendation = spread_pick,
      predicted_score = paste0(game$predicted_home_score, "-", game$predicted_away_score),
      cover_probability = sprintf("%.1f%%", game$spread_cover_probability * 100),
      confidence = sprintf("%.3f", game$spread_confidence),
      edge_vs_line = sprintf("%.1f pts", abs(game$predicted_margin - game$spread_line))
    )
    
    recommendations[[length(recommendations) + 1]] <- rec
  }
}

bet_recommendations <- bind_rows(recommendations)

# ============================================================================
# STEP 10: DISPLAY & SAVE RESULTS
# ============================================================================

cat(paste(rep("=", 80), collapse = ""), "\n")
cat("ðŸŽ¯ 2025 NFL PREDICTIONS & BET RECOMMENDATIONS\n")
cat(paste(rep("=", 80), collapse = ""), "\n\n")

cat(sprintf("Total Upcoming Games: %d\n", nrow(predictions)))
cat(sprintf("Bet Recommendations: %d\n\n", nrow(bet_recommendations)))

if (nrow(bet_recommendations) > 0) {
  cat("RECOMMENDED BETS:\n")
  cat(paste(rep("-", 80), collapse = ""), "\n\n")
  
  # Print each recommendation
  for (i in 1:nrow(bet_recommendations)) {
    bet <- bet_recommendations[i, ]
    
    cat(sprintf("Week %d - %s\n", bet$week, bet$gameday))
    cat(sprintf("  %s\n", bet$matchup))
    cat(sprintf("  BET TYPE: %s\n", bet$bet_type))
    cat(sprintf("  PICK: %s\n", bet$recommendation))
    cat(sprintf("  Predicted Score: %s\n", bet$predicted_score))
    
    if (bet$bet_type == "MONEYLINE") {
      cat(sprintf("  Win Probability: %s | Confidence: %s\n", 
                  bet$win_probability, bet$confidence))
    } else {
      cat(sprintf("  Cover Probability: %s | Edge: %s | Confidence: %s\n",
                  bet$cover_probability, bet$edge_vs_line, bet$confidence))
    }
    cat("\n")
  }
} else {
  cat("âš ï¸  No bets meet the confidence thresholds\n")
  cat("   (This is actually good - it means being selective!)\n\n")
}

# Save full predictions
cat("\nðŸ’¾ Saving results...\n")

# Save all predictions
write.csv(predictions %>%
            select(week, gameday, home_team, away_team,
                   predicted_home_score, predicted_away_score,
                   predicted_winner, predicted_margin,
                   home_win_probability, spread_line,
                   spread_cover_probability, prediction_uncertainty,
                   model_agreement),
          file.path(results_dir, "all_2025_predictions.csv"),
          row.names = FALSE)

# Save bet recommendations
if (nrow(bet_recommendations) > 0) {
  write.csv(bet_recommendations,
            file.path(results_dir, "bet_recommendations.csv"),
            row.names = FALSE)
}

cat(sprintf("\nâœ“ Results saved to %s/\n", results_dir))
cat("  - all_2025_predictions.csv (all upcoming games)\n")
if (nrow(bet_recommendations) > 0) {
  cat("  - bet_recommendations.csv (recommended bets)\n")
}

cat("\n", paste(rep("=", 80), collapse = ""), "\n")
cat("ðŸŽ‰ PREDICTIONS COMPLETE!\n")
cat(paste(rep("=", 80), collapse = ""), "\n\n")

cat("ðŸ“Œ Summary:\n")
cat(sprintf("  âœ“ Trained on %d games from 2024 season\n", nrow(X_train)))
cat(sprintf("  âœ“ Predicted %d upcoming 2025 games\n", nrow(predictions)))
cat(sprintf("  âœ“ Generated %d high-confidence betting recommendations\n", nrow(bet_recommendations)))
cat("\n")
