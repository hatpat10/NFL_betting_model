"""
NFL Betting Model - Enhanced Weekly Predictions
================================================
Generate predictions using rich feature models

Input:  db/margin_model_rich.joblib
        db/total_model_rich.joblib  
        data/processed/model_table_rich.parquet
Output: reports/week_{season}_{week}_predictions_rich.csv

Usage:
    python predict_week_enhanced.py --season 2025 --week 10
"""

import os
import argparse
import pandas as pd
import numpy as np
import joblib
from scipy.stats import norm

# ============================================================================
# PATHS
# ============================================================================

BASE_DIR = "C:/Users/Patsc/Documents/NFL_betting_model"
DATA_DIR = os.path.join(BASE_DIR, "data")
PROCESSED_DIR = os.path.join(DATA_DIR, "processed")
MODEL_DIR = os.path.join(BASE_DIR, "db")
REPORTS_DIR = os.path.join(BASE_DIR, "reports")

MODEL_TABLE = os.path.join(PROCESSED_DIR, "model_table_rich.parquet")
MARGIN_MODEL = os.path.join(MODEL_DIR, "margin_model_rich.joblib")
TOTAL_MODEL = os.path.join(MODEL_DIR, "total_model_rich.joblib")

os.makedirs(REPORTS_DIR, exist_ok=True)

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

parser = argparse.ArgumentParser(description="Generate enhanced weekly predictions")
parser.add_argument("--season", type=int, required=True, help="NFL season (e.g., 2025)")
parser.add_argument("--week", type=int, required=True, help="Week number (e.g., 10)")
args = parser.parse_args()

SEASON = args.season
WEEK = args.week

print("\n" + "="*70)
print(f"   🔮 GENERATING ENHANCED PREDICTIONS")
print(f"   Season {SEASON} | Week {WEEK}")
print("="*70 + "\n")

# ============================================================================
# STEP 1: Load models
# ============================================================================

print("[1/4] Loading trained models...")

if not os.path.exists(MARGIN_MODEL) or not os.path.exists(TOTAL_MODEL):
    raise FileNotFoundError(
        f"❌ Models not found!\n"
        f"   Run: python train_models_enhanced.py"
    )

margin_model = joblib.load(MARGIN_MODEL)
total_model = joblib.load(TOTAL_MODEL)

print(f"   ✅ Margin model loaded")
print(f"   ✅ Total model loaded\n")

# ============================================================================
# STEP 2: Load week data
# ============================================================================

print(f"[2/4] Loading Week {WEEK} games...")

if not os.path.exists(MODEL_TABLE):
    raise FileNotFoundError(
        f"❌ Missing {MODEL_TABLE}\n"
        f"   Run: python build_model_table_enhanced.py --season {SEASON}"
    )

df = pd.read_parquet(MODEL_TABLE)
week_games = df[(df["season"] == SEASON) & (df["week"] == WEEK)].copy()

if len(week_games) == 0:
    raise ValueError(f"❌ No games found for Season {SEASON}, Week {WEEK}")

print(f"   ✅ Found {len(week_games)} games\n")

# ============================================================================
# STEP 3: Generate predictions
# ============================================================================

print("[3/4] Generating predictions...")

# Get feature columns (same as used in training)
feature_cols = [c for c in df.columns if c.startswith("delta_") or c in ["home_injury_impact", "away_injury_impact"]]
feature_cols = [c for c in feature_cols if c in week_games.columns]

print(f"   📊 Using {len(feature_cols)} features\n")

# Prepare features
X = week_games[feature_cols].apply(pd.to_numeric, errors='coerce').replace([np.inf, -np.inf], np.nan)

# Check for missing features
if X.isna().any().any():
    print("   ⚠️  WARNING: Some features have NaN values")
    print("      This is normal for Week 1 or incomplete data")
    print("      Predictions may be less reliable\n")
    X = X.fillna(0)  # Conservative fallback

# Predict margin and total
predicted_margin = margin_model.predict(X.values)
predicted_total = total_model.predict(X.values)

# Add predictions to dataframe
week_games["predicted_margin_home_minus_away"] = predicted_margin
week_games["predicted_total_points"] = predicted_total

# Calculate individual scores
# margin = home - away
# total = home + away
# Therefore:
#   home = (total + margin) / 2
#   away = (total - margin) / 2

week_games["predicted_home_score"] = (predicted_total + predicted_margin) / 2
week_games["predicted_away_score"] = (predicted_total - predicted_margin) / 2

# Win probability (from margin using normal CDF with σ≈13.5)
week_games["home_win_prob"] = norm.cdf(predicted_margin / 13.5)

# Model spread (negative of margin, since spread is for home team)
week_games["model_home_spread"] = -predicted_margin

print("   ✅ Predictions generated\n")

# ============================================================================
# STEP 4: Format and save output
# ============================================================================

print("[4/4] Formatting output...")

# Select output columns
output_cols = [
    "season", "week",
    "home_team", "away_team",
    "predicted_margin_home_minus_away",
    "home_win_prob",
    "predicted_home_score",
    "predicted_away_score",
    "predicted_total_points",
    "model_home_spread"
]

# Add actual scores if available
if "home_score" in week_games.columns:
    output_cols.extend(["home_score", "away_score"])

# Add vegas lines if available
if "spread_line" in week_games.columns:
    output_cols.append("spread_line")
    week_games["edge_home_spread_pts"] = week_games["model_home_spread"] - week_games["spread_line"]
    output_cols.append("edge_home_spread_pts")

if "total_line" in week_games.columns:
    output_cols.append("total_line")
    week_games["edge_total_pts"] = week_games["predicted_total_points"] - week_games["total_line"]
    output_cols.append("edge_total_pts")

# Filter to available columns
output_cols = [c for c in output_cols if c in week_games.columns]
output_df = week_games[output_cols].copy()

# Round to 1 decimal
numeric_cols = output_df.select_dtypes(include=[np.number]).columns
output_df[numeric_cols] = output_df[numeric_cols].round(1)

# Save CSV
output_file = os.path.join(REPORTS_DIR, f"week_{SEASON}_{WEEK}_predictions_rich.csv")
output_df.to_csv(output_file, index=False)

print(f"   ✅ Saved: {output_file}\n")

# ============================================================================
# SUMMARY
# ============================================================================

print("="*70)
print("   ✅ PREDICTIONS COMPLETE")
print("="*70)

print(f"\n📊 Week {WEEK} Predictions:\n")

for idx, row in output_df.iterrows():
    home = row['home_team']
    away = row['away_team']
    margin = row['predicted_margin_home_minus_away']
    home_score = row['predicted_home_score']
    away_score = row['predicted_away_score']
    win_prob = row['home_win_prob']
    
    # Determine favorite
    if margin > 0:
        favorite = home
        spread = abs(margin)
    else:
        favorite = away
        spread = abs(margin)
    
    print(f"   {away} @ {home}")
    print(f"      Projected: {home} {home_score:.1f} - {away} {away_score:.1f}")
    print(f"      Favorite: {favorite} by {spread:.1f}")
    print(f"      Win Prob: {home} {win_prob*100:.1f}%")
    
    # Show edges if available
    if "edge_home_spread_pts" in row:
        edge = row["edge_home_spread_pts"]
        if abs(edge) >= 2.0:
            print(f"      ⚡ Edge: {abs(edge):.1f} pts vs closing spread")
    
    print()

print(f"\n💾 Full details: {output_file}")
print(f"\n🎯 Next Steps:")
print(f"   • Review predictions in Excel or CSV viewer")
print(f"   • Compare to closing lines for edges")
print(f"   • Track results after games complete\n")
