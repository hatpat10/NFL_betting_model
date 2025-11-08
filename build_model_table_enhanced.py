"""
NFL Betting Model - Enhanced Model Table Builder
==================================================
Merges schedule + rich team features → model_table_rich.parquet

Uses: team_week_rich.parquet (from bridge_og_to_python.py)
Creates: model_table_rich.parquet (training-ready dataset)

Features:
- 20+ rich features from og_pipeline.R
- Home/away matchup deltas
- Context features (rest, injuries, weather proxies)
- Situational stats (3rd down, red zone, 2-min)

Usage:
    python build_model_table_enhanced.py --season 2025
"""

import os
import argparse
import pandas as pd
import numpy as np

# ============================================================================
# PATHS
# ============================================================================

BASE_DIR = "C:/Users/Patsc/Documents/NFL_betting_model"
DATA_DIR = os.path.join(BASE_DIR, "data")
RAW_DIR = os.path.join(DATA_DIR, "raw")
PROCESSED_DIR = os.path.join(DATA_DIR, "processed")

SCHED_FILE = os.path.join(RAW_DIR, "schedules.parquet")
TEAMW_FILE = os.path.join(PROCESSED_DIR, "team_week_rich.parquet")
OUTPUT_FILE = os.path.join(PROCESSED_DIR, "model_table_rich.parquet")

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

parser = argparse.ArgumentParser(description="Build enhanced model table")
parser.add_argument("--season", type=int, required=True, help="NFL season (e.g., 2025)")
args = parser.parse_args()

SEASON = args.season

print("\n" + "="*70)
print(f"   📊 BUILDING ENHANCED MODEL TABLE")
print(f"   Season {SEASON}")
print("="*70 + "\n")

# ============================================================================
# STEP 1: Load data
# ============================================================================

print("[1/5] Loading schedule...")
if not os.path.exists(SCHED_FILE):
    raise FileNotFoundError(
        f"❌ Missing {SCHED_FILE}\n"
        f"   Run: Rscript R/01_ingest_historical.R"
    )

sched = pd.read_parquet(SCHED_FILE)

# Filter to REG season only
if "game_type" in sched.columns:
    sched = sched[sched["game_type"].fillna("").str.upper().isin(
        ["REG", "REGULAR", "REGULAR_SEASON", ""]
    )]

# Filter to target season
sched = sched[sched["season"] == SEASON].copy()
print(f"   ✅ {len(sched)} games for {SEASON} season\n")

print("[2/5] Loading rich team features...")
if not os.path.exists(TEAMW_FILE):
    raise FileNotFoundError(
        f"❌ Missing {TEAMW_FILE}\n"
        f"   Run: python bridge_og_to_python.py --season {SEASON} --week <WEEK>"
    )

tw = pd.read_parquet(TEAMW_FILE)
print(f"   ✅ {len(tw)} team-weeks | {tw.columns.size} features\n")

# ============================================================================
# STEP 2: Merge home team features
# ============================================================================

print("[3/5] Merging home team features...")

home_cols = {c: f"home_{c}" for c in tw.columns if c not in ["team", "season", "week"]}
home = tw.rename(columns={"team": "home_team", **home_cols})

merged = sched.merge(
    home,
    on=["season", "week", "home_team"],
    how="left"
)

home_features = [c for c in merged.columns if c.startswith("home_") and c != "home_team"]
print(f"   ✅ Added {len(home_features)} home features\n")

# ============================================================================
# STEP 3: Merge away team features
# ============================================================================

print("[4/5] Merging away team features...")

away_cols = {c: f"away_{c}" for c in tw.columns if c not in ["team", "season", "week"]}
away = tw.rename(columns={"team": "away_team", **away_cols})

merged = merged.merge(
    away,
    on=["season", "week", "away_team"],
    how="left"
)

away_features = [c for c in merged.columns if c.startswith("away_") and c != "away_team"]
print(f"   ✅ Added {len(away_features)} away features\n")

# ============================================================================
# STEP 4: Create matchup delta features
# ============================================================================

print("[5/5] Creating matchup delta features...")

# Define feature pairs to create deltas
feature_bases = [
    # Core EPA
    "off_avg_epa_pass",
    "off_avg_epa_run",
    "off_success_rate",
    "def_avg_epa_per_play",
    "def_success_rate_allowed",
    
    # Rolling windows
    "off_epa_l3",
    "off_sr_l3",
    "def_epa_l3",
    "def_sr_l3",
    
    # Situational
    "off_third_down_rate",
    "off_red_zone_td_rate",
    "off_two_min_td_rate",
    "def_third_down_rate",
    "def_turnover_rate",
    
    # Pace
    "off_plays_per_game",
    
    # Context (if available)
    "injury_impact",
]

delta_count = 0
for base in feature_bases:
    home_col = f"home_{base}"
    away_col = f"away_{base}"
    delta_col = f"delta_{base}"
    
    if home_col in merged.columns and away_col in merged.columns:
        merged[delta_col] = merged[home_col] - merged[away_col]
        delta_count += 1

print(f"   ✅ Created {delta_count} delta features\n")

# ============================================================================
# STEP 5: Add target variables (margin, total)
# ============================================================================

print("🎯 Adding target variables...")

# Margin = home_score - away_score (positive = home win)
if "home_score" in merged.columns and "away_score" in merged.columns:
    merged["margin"] = merged["home_score"] - merged["away_score"]
    merged["total_points"] = merged["home_score"] + merged["away_score"]
    
    completed = merged["margin"].notna().sum()
    print(f"   ✅ {completed} games with results (targets)\n")
else:
    merged["margin"] = np.nan
    merged["total_points"] = np.nan
    print("   ⚠️  No scores in schedule (all games future)\n")

# ============================================================================
# STEP 6: Data quality checks
# ============================================================================

print("🔍 Data quality checks...")

# Check for NaN in features
feature_cols = [c for c in merged.columns if c.startswith("delta_") or c.startswith("home_") or c.startswith("away_")]
feature_cols = [c for c in feature_cols if c not in ["home_team", "away_team", "home_score", "away_score"]]

nan_counts = merged[feature_cols].isna().sum()
features_with_nans = nan_counts[nan_counts > 0]

if len(features_with_nans) > 0:
    print(f"\n   ⚠️  {len(features_with_nans)} features with NaN values:")
    for feat, count in features_with_nans.head(10).items():
        print(f"      • {feat}: {count} NaN")
    print("\n   💡 NaN values are expected for:")
    print("      • Future games (no scores yet)")
    print("      • Week 1 (no rolling windows yet)")
    print("      • Teams with limited history\n")
else:
    print("   ✅ No NaN values in features\n")

# ============================================================================
# STEP 7: Save enhanced model table
# ============================================================================

print(f"💾 Saving to: {OUTPUT_FILE}\n")

# Convert all numeric columns
numeric_cols = merged.select_dtypes(include=[np.number]).columns
for col in numeric_cols:
    merged[col] = pd.to_numeric(merged[col], errors='coerce')

merged.to_parquet(OUTPUT_FILE, index=False, engine='pyarrow')

print("="*70)
print("   ✅ ENHANCED MODEL TABLE COMPLETE")
print("="*70)
print(f"\n📊 Summary:")
print(f"   • Games: {len(merged)}")
print(f"   • Features: {len(feature_cols)}")
print(f"   • Delta features: {delta_count}")
print(f"   • Completed games: {completed if 'completed' in locals() else 0}")
print(f"   • Output: {OUTPUT_FILE}")

print(f"\n🎯 Next Steps:")
print(f"   python py/train_models_enhanced.py\n")

# ============================================================================
# BONUS: Feature breakdown
# ============================================================================

print("\n📋 Feature Breakdown:")
print("─" * 70)

feature_groups = {
    'EPA Features': len([c for c in feature_cols if 'epa' in c.lower()]),
    'Success Rate': len([c for c in feature_cols if 'success' in c.lower()]),
    'Situational': len([c for c in feature_cols if any(x in c.lower() for x in ['third', 'red_zone', 'two_min'])]),
    'Pace': len([c for c in feature_cols if 'pace' in c.lower() or 'plays_per' in c.lower()]),
    'Context': len([c for c in feature_cols if any(x in c.lower() for x in ['injury', 'rest', 'weather'])]),
    'Delta (Matchup)': len([c for c in feature_cols if c.startswith('delta_')])
}

for group_name, count in feature_groups.items():
    print(f"{group_name:20s}: {count:3d} features")

print("\n" + "="*70 + "\n")
