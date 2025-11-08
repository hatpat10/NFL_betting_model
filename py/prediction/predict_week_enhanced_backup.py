"""
Enhanced Week Predictions - Uses Both Margin + Total Models
===========================================================
Improvements over original predict_week.py:
1. Uses ALL features (not just 2)
2. Predicts both margin AND total independently
3. Calculates implied scores from both predictions
4. Provides confidence metrics
5. Compares to Vegas lines if available
"""

import argparse
import os
import pandas as pd
import joblib
import numpy as np
from py.utils import win_prob_from_margin

# Paths
SCHED = "data/raw/schedules.parquet"
MODEL_TABLE = "data/processed/model_table.parquet"
MARGIN_MODEL = "db/margin_model.joblib"
TOTAL_MODEL = "db/total_model.joblib"
FEATURE_LIST = "db/feature_list.joblib"
REPORTS_DIR = "reports"

# Parse arguments
parser = argparse.ArgumentParser()
parser.add_argument("--season", type=int, required=True)
parser.add_argument("--week", type=int, required=True)
args = parser.parse_args()

print("\n" + "="*60)
print(f"  WEEK {args.week} PREDICTIONS (Season {args.season})")
print("="*60 + "\n")

# ============================================================================
# STEP 1: Load Models and Features
# ============================================================================

print("[1/5] Loading trained models...")

if not os.path.exists(MARGIN_MODEL):
    raise SystemExit(
        f"Missing {MARGIN_MODEL}\n"
        "Run: python train_models_enhanced.py first"
    )

margin_model = joblib.load(MARGIN_MODEL)
total_model = joblib.load(TOTAL_MODEL)
feature_cols = joblib.load(FEATURE_LIST)

print(f"   ✓ Loaded margin model")
print(f"   ✓ Loaded total model")
print(f"   ✓ Using {len(feature_cols)} features")

# ============================================================================
# STEP 2: Load Schedule for Target Week
# ============================================================================

print(f"\n[2/5] Loading Week {args.week} schedule...")

if not os.path.exists(SCHED):
    raise SystemExit(
        f"Missing {SCHED}\n"
        "Run: Rscript export_features_to_python.R first"
    )

sched = pd.read_parquet(SCHED)

if "game_type" in sched.columns:
    sched = sched[sched["game_type"].fillna("").str.upper().isin(
        ["REG", "REGULAR", "REGULAR_SEASON", ""]
    )]

week_games = sched[
    (sched["season"] == args.season) & (sched["week"] == args.week)
].copy()

if week_games.empty:
    raise SystemExit(f"No games found for season={args.season}, week={args.week}")

print(f"   Found {len(week_games)} games")

# ============================================================================
# STEP 3: Load Model Table with Features
# ============================================================================

print(f"[3/5] Loading features for Week {args.week}...")

if not os.path.exists(MODEL_TABLE):
    raise SystemExit(
        f"Missing {MODEL_TABLE}\n"
        "Run: Rscript export_features_to_python.R first"
    )

model_table = pd.read_parquet(MODEL_TABLE)

week_features = model_table[
    (model_table["season"] == args.season) & 
    (model_table["week"] == args.week)
].copy()

if week_features.empty:
    raise SystemExit(
        f"No features found for Week {args.week}\n"
        "Make sure your R pipeline has generated stats through Week {args.week - 1}"
    )

print(f"   Loaded features for {len(week_features)} games")

# ============================================================================
# STEP 4: Generate Predictions
# ============================================================================

print(f"[4/5] Generating predictions...")

# Extract features
X = week_features[feature_cols].fillna(0.0).values

# Predict
pred_margin = margin_model.predict(X)
pred_total = total_model.predict(X)

# Calculate implied scores
# From margin and total: home = (total + margin) / 2, away = (total - margin) / 2
pred_home_score = (pred_total + pred_margin) / 2.0
pred_away_score = (pred_total - pred_margin) / 2.0

# Win probabilities
win_prob_home = [win_prob_from_margin(m) for m in pred_margin]

# Build output
predictions = pd.DataFrame({
    "season": week_features["season"].values,
    "week": week_features["week"].values,
    "home_team": week_features["home_team"].values,
    "away_team": week_features["away_team"].values,
    "gameday": week_games["gameday"].values if "gameday" in week_games.columns else None,
    
    # Model predictions
    "predicted_margin_home_minus_away": pred_margin,
    "predicted_total": pred_total,
    "predicted_home_score": pred_home_score,
    "predicted_away_score": pred_away_score,
    "home_win_prob": win_prob_home,
    
    # Model spread (negative for betting convention: negative = home favored)
    "model_home_spread": -pred_margin,
})

# Add Vegas lines if available
if "spread_line" in week_features.columns:
    predictions["vegas_home_spread"] = week_features["spread_line"].values
    predictions["edge_spread_pts"] = predictions["model_home_spread"] - predictions["vegas_home_spread"]

if "total_line" in week_features.columns:
    predictions["vegas_total"] = week_features["total_line"].values
    predictions["edge_total_pts"] = predictions["predicted_total"] - predictions["vegas_total"]

# Add matchup column for readability
predictions["matchup"] = predictions["away_team"] + " @ " + predictions["home_team"]

# Sort by gameday
if "gameday" in predictions.columns:
    predictions = predictions.sort_values("gameday")

print(f"   Generated predictions for {len(predictions)} games")

# ============================================================================
# STEP 5: Save and Display
# ============================================================================

print(f"[5/5] Saving predictions...")

os.makedirs(REPORTS_DIR, exist_ok=True)
csv_path = os.path.join(REPORTS_DIR, f"week_{args.season}_{args.week}_predictions.csv")
predictions.to_csv(csv_path, index=False)

print(f"   ✓ Saved: {csv_path}")

# Display summary
print("\n" + "="*60)
print(f"  WEEK {args.week} PREDICTIONS SUMMARY")
print("="*60 + "\n")

display_cols = [
    "matchup", 
    "model_home_spread", 
    "predicted_total",
    "home_win_prob"
]

# Add edge columns if available
if "edge_spread_pts" in predictions.columns:
    display_cols.extend(["vegas_home_spread", "edge_spread_pts"])

summary = predictions[display_cols].copy()
summary["home_win_prob"] = (summary["home_win_prob"] * 100).round(1)
summary["model_home_spread"] = summary["model_home_spread"].round(1)
summary["predicted_total"] = summary["predicted_total"].round(1)

if "edge_spread_pts" in summary.columns:
    summary["vegas_home_spread"] = summary["vegas_home_spread"].round(1)
    summary["edge_spread_pts"] = summary["edge_spread_pts"].round(1)

print(summary.to_string(index=False))

# Highlight big edges
if "edge_spread_pts" in predictions.columns:
    big_edges = predictions[predictions["edge_spread_pts"].abs() >= 2.5].copy()
    
    if not big_edges.empty:
        print("\n" + "="*60)
        print(f"  🎯 GAMES WITH EDGE ≥ 2.5 POINTS")
        print("="*60 + "\n")
        
        for _, game in big_edges.iterrows():
            edge = game["edge_spread_pts"]
            pick_side = "HOME" if edge > 0 else "AWAY"
            pick_team = game["home_team"] if edge > 0 else game["away_team"]
            
            print(f"{game['matchup']:30s}")
            print(f"   Model: {game['model_home_spread']:+5.1f} | Vegas: {game['vegas_home_spread']:+5.1f} | Edge: {edge:+5.1f}")
            print(f"   → PICK: {pick_team} ({pick_side})\n")

print("\n💾 Full predictions saved to:", csv_path)
print("🎯 Next: Compare to market with line_movement_report.py\n")
