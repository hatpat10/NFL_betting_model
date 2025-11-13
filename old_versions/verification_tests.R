# ============================================================================
# VERIFICATION SCRIPT - Test if Your Fixes Worked
# ============================================================================
# Run this AFTER making changes to verify everything is working correctly
# 
# Usage:
# 1. Make the 4 changes to your pipeline
# 2. Generate predictions for Week 5
# 3. Run this script to verify the fixes worked

# ============================================================================
# SETUP
# ============================================================================

library(dplyr)
library(readxl)

BASE_DIR <- "C:/Users/Patsc/Documents/nfl_model_v2"
TEST_WEEK <- 5  # Change this to whatever week you generated

# ============================================================================
# TEST 1: Check if prediction file exists
# ============================================================================

cat("\n")
cat("â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—\n")
cat("â•‘           VERIFICATION TEST - Model Fixes v2.1                 â•‘\n")
cat("â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•\n")
cat("\n")

cat("[TEST 1] Checking if prediction file exists...\n")

pred_file <- file.path(BASE_DIR, paste0("week", TEST_WEEK), 
                       paste0("Week_", TEST_WEEK, "_Model_Output.xlsx"))

if (file.exists(pred_file)) {
  cat("      âœ… PASS: File found at", pred_file, "\n\n")
} else {
  cat("      âŒ FAIL: File not found!\n")
  cat("      Expected:", pred_file, "\n")
  cat("      â†’ Run the pipeline first to generate predictions\n\n")
  stop("Cannot continue without prediction file")
}

# ============================================================================
# TEST 2: Load and check predictions
# ============================================================================

cat("[TEST 2] Loading predictions...\n")

tryCatch({
  predictions <- read_excel(pred_file, sheet = "Betting Summary")
  cat("      âœ… PASS: Predictions loaded successfully\n")
  cat("      Games found:", nrow(predictions), "\n\n")
}, error = function(e) {
  cat("      âŒ FAIL: Could not load predictions\n")
  cat("      Error:", e$message, "\n\n")
  stop("Cannot continue")
})

# ============================================================================
# TEST 3: Check prediction magnitude (KEY TEST!)
# ============================================================================

cat("[TEST 3] Checking prediction magnitudes...\n")

avg_margin <- mean(abs(predictions$`Predicted Margin`), na.rm = TRUE)
max_margin <- max(abs(predictions$`Predicted Margin`), na.rm = TRUE)
min_margin <- min(abs(predictions$`Predicted Margin`), na.rm = TRUE)

cat("      Average predicted margin:", round(avg_margin, 2), "points\n")
cat("      Maximum predicted margin:", round(max_margin, 2), "points\n")
cat("      Minimum predicted margin:", round(min_margin, 2), "points\n")

if (avg_margin >= 7 && avg_margin <= 13) {
  cat("      âœ… PASS: Average margin looks good! (target: 8-12 points)\n")
  test3_pass <- TRUE
} else if (avg_margin < 4) {
  cat("      âŒ FAIL: Average margin too low!\n")
  cat("      â†’ AMPLIFICATION_FACTOR not being applied\n")
  cat("      â†’ Double-check Step 4 of the fix\n")
  test3_pass <- FALSE
} else if (avg_margin > 15) {
  cat("      âš ï¸  WARNING: Average margin very high\n")
  cat("      â†’ AMPLIFICATION_FACTOR might be too aggressive\n")
  cat("      â†’ Try reducing to 1.5 or 1.8\n")
  test3_pass <- TRUE  # Still pass, just needs tuning
} else {
  cat("      âš ï¸  Margin is acceptable but could be better\n")
  test3_pass <- TRUE
}
cat("\n")

# ============================================================================
# TEST 4: Check for blowout predictions
# ============================================================================

cat("[TEST 4] Checking for blowout predictions...\n")

blowouts <- predictions %>%
  filter(abs(`Predicted Margin`) > 14)

num_blowouts <- nrow(blowouts)

cat("      Blowouts predicted (>14 pts):", num_blowouts, "\n")

if (num_blowouts >= 1) {
  cat("      âœ… PASS: Model is predicting some blowouts\n")
  if (num_blowouts > 0 && num_blowouts <= nrow(predictions)) {
    cat("      Top blowout predictions:\n")
    top_blowouts <- blowouts %>%
      arrange(desc(abs(`Predicted Margin`))) %>%
      head(3) %>%
      mutate(Matchup = paste(`Away Team`, "@", `Home Team`),
             Margin = `Predicted Margin`) %>%
      select(Matchup, Margin)
    print(top_blowouts, row.names = FALSE)
  }
  test4_pass <- TRUE
} else {
  cat("      âŒ FAIL: No blowouts predicted\n")
  cat("      â†’ Model still too conservative\n")
  cat("      â†’ Increase AMPLIFICATION_FACTOR to 2.2 or 2.5\n")
  test4_pass <- FALSE
}
cat("\n")

# ============================================================================
# TEST 5: Check prediction distribution
# ============================================================================

cat("[TEST 5] Analyzing prediction distribution...\n")

close_games <- sum(abs(predictions$`Predicted Margin`) <= 3)
medium_games <- sum(abs(predictions$`Predicted Margin`) > 3 & 
                      abs(predictions$`Predicted Margin`) <= 10)
big_games <- sum(abs(predictions$`Predicted Margin`) > 10)

total_games <- nrow(predictions)

cat("      Very close (0-3 pts):", close_games, 
    sprintf("(%.1f%%)", close_games/total_games*100), "\n")
cat("      Medium (3-10 pts):  ", medium_games, 
    sprintf("(%.1f%%)", medium_games/total_games*100), "\n")
cat("      Big margins (>10):  ", big_games, 
    sprintf("(%.1f%%)", big_games/total_games*100), "\n")

# Good distribution should be roughly:
# Close: 25-35%
# Medium: 40-50%
# Big: 20-30%

if (close_games/total_games > 0.6) {
  cat("      âš ï¸  WARNING: Too many close games predicted\n")
  cat("      â†’ Model still conservative\n")
  test5_pass <- FALSE
} else if (big_games/total_games < 0.15) {
  cat("      âš ï¸  WARNING: Not enough big margins\n")
  test5_pass <- FALSE
} else {
  cat("      âœ… PASS: Distribution looks reasonable\n")
  test5_pass <- TRUE
}
cat("\n")

# ============================================================================
# FINAL RESULTS
# ============================================================================

cat("â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—\n")
cat("â•‘                    VERIFICATION RESULTS                        â•‘\n")
cat("â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•\n\n")

all_passed <- test3_pass && test4_pass && test5_pass

if (all_passed) {
  cat("ðŸŽ‰ ALL TESTS PASSED! ðŸŽ‰\n\n")
  cat("Your fixes are working correctly!\n\n")
  cat("Next steps:\n")
  cat("1. Generate predictions for weeks 5, 6, 7\n")
  cat("2. Run backtest: source('proper_backtest.R')\n")
  cat("3. Check if hit rate improved to 55-60%\n")
  cat("4. If MAE is 8-10, you're golden!\n")
  cat("5. If still too conservative, increase AMPLIFICATION_FACTOR to 2.2\n")
  cat("6. If too aggressive, decrease to 1.8\n\n")
} else {
  cat("âš ï¸  SOME TESTS FAILED\n\n")
  cat("Issues detected:\n")
  
  if (!test3_pass) {
    cat("- Prediction magnitude not in target range\n")
    cat("  â†’ Check that AMPLIFICATION_FACTOR is being applied\n")
  }
  
  if (!test4_pass) {
    cat("- No blowouts being predicted\n")
    cat("  â†’ Model too conservative, increase amplification\n")
  }
  
  if (!test5_pass) {
    cat("- Prediction distribution skewed\n")
    cat("  â†’ Fine-tune AMPLIFICATION_FACTOR\n")
  }
  
  cat("\nTroubleshooting:\n")
  cat("1. Double-check Step 4 in QUICK_FIX_GUIDE.R\n")
  cat("2. Make sure you multiplied by AMPLIFICATION_FACTOR\n")
  cat("3. Verify AMPLIFICATION_FACTOR = 2.0 at top of file\n")
  cat("4. If stuck, upload your prediction formula and I'll help!\n\n")
}

# ============================================================================
# COMPARISON WITH TARGET
# ============================================================================

cat("COMPARISON TO TARGET:\n")
cat("â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€\n")
cat(sprintf("Average Margin:  %.1f pts (Target: 8-12 pts)\n", avg_margin))
cat(sprintf("Blowouts:        %d games (Target: 2-4 games per week)\n", num_blowouts))
cat(sprintf("Close Games:     %d games (Target: 3-5 games per week)\n", close_games))
cat("\n")

# ============================================================================
# DETAILED GAME-BY-GAME VIEW
# ============================================================================

cat("PREDICTED MARGINS (sorted by magnitude):\n")
cat("â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€\n")

games_sorted <- predictions %>%
  mutate(
    Matchup = paste(`Away Team`, "@", `Home Team`),
    Margin = `Predicted Margin`,
    Magnitude = abs(Margin)
  ) %>%
  arrange(desc(Magnitude)) %>%
  select(Matchup, Margin, Magnitude)

print(games_sorted, row.names = FALSE, n = Inf)

cat("\n")
cat("â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•\n")
cat("VERIFICATION COMPLETE\n")
cat("â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•\n")
