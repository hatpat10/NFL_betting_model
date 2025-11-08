"""
NFL Betting Model - Feature Bridge Script
==========================================
Converts og_pipeline.R rich CSV outputs → Python-ready parquet format

Input:  week9/ CSVs from og_pipeline.R
Output: data/processed/team_week_rich.parquet (for Python models)

Usage:
    python bridge_og_to_python.py --season 2025 --week 9
"""

import os
import argparse
import pandas as pd
import numpy as np

# ============================================================================
# CONFIGURATION
# ============================================================================

BASE_DIR = "C:/Users/Patsc/Documents/NFL_betting_model"
DATA_DIR = os.path.join(BASE_DIR, "data")
RAW_DIR = os.path.join(DATA_DIR, "raw")
PROCESSED_DIR = os.path.join(DATA_DIR, "processed")

# Ensure output directory exists
os.makedirs(PROCESSED_DIR, exist_ok=True)

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

parser = argparse.ArgumentParser(description="Bridge og_pipeline.R → Python features")
parser.add_argument("--season", type=int, required=True, help="NFL season (e.g., 2025)")
parser.add_argument("--week", type=int, required=True, help="Week number (e.g., 9)")
args = parser.parse_args()

SEASON = args.season
WEEK = args.week

print("\n" + "="*70)
print(f"   🌉 OG PIPELINE → PYTHON BRIDGE")
print(f"   Season {SEASON} | Week {WEEK}")
print("="*70 + "\n")

# ============================================================================
# STEP 1: Load og_pipeline.R outputs
# ============================================================================

week_dir = os.path.join(BASE_DIR, f"week{WEEK}")

if not os.path.exists(week_dir):
    raise FileNotFoundError(
        f"❌ Missing week{WEEK}/ directory!\n"
        f"   Run: Rscript og_pipeline.R with WEEK <- {WEEK}\n"
        f"   Expected: {week_dir}"
    )

print(f"📂 Reading from: {week_dir}\n")

# Load core feature files
offense_file = os.path.join(week_dir, "offense_weekly.csv")
defense_file = os.path.join(week_dir, "defense_weekly.csv")
weather_file = os.path.join(week_dir, "weather_data.csv")
injuries_file = os.path.join(week_dir, "injuries_summary.csv")
schedule_file = os.path.join(week_dir, "schedule_rest.csv")

# Check required files
required_files = [offense_file, defense_file]
for fpath in required_files:
    if not os.path.exists(fpath):
        raise FileNotFoundError(f"❌ Required file missing: {fpath}")

print("[1/5] Loading offensive features...")
offense = pd.read_csv(offense_file)
print(f"      ✅ {len(offense)} team-weeks | {offense.columns.size} columns")

print("[2/5] Loading defensive features...")
defense = pd.read_csv(defense_file)
print(f"      ✅ {len(defense)} team-weeks | {defense.columns.size} columns")

# Load context files (optional)
print("[3/5] Loading weather data...")
if os.path.exists(weather_file):
    weather = pd.read_csv(weather_file)
    print(f"      ✅ {len(weather)} games with weather")
else:
    weather = pd.DataFrame()
    print("      ⚠️  No weather_data.csv found")

print("[4/5] Loading injury data...")
if os.path.exists(injuries_file):
    injuries = pd.read_csv(injuries_file)
    print(f"      ✅ {len(injuries)} team-weeks with injuries")
else:
    injuries = pd.DataFrame()
    print("      ⚠️  No injuries_summary.csv found")

print("[5/5] Loading schedule/rest data...")
if os.path.exists(schedule_file):
    schedule = pd.read_csv(schedule_file)
    print(f"      ✅ {len(schedule)} games with rest/schedule factors\n")
else:
    schedule = pd.DataFrame()
    print("      ⚠️  No schedule_rest.csv found\n")

# ============================================================================
# STEP 2: Merge offense + defense into unified team-week table
# ============================================================================

print("🔄 Merging offensive + defensive features...\n")

# Rename columns for clarity
offense_cols = {
    'offense_team': 'team',
    'week': 'week'
}
defense_cols = {
    'defense_team': 'team',
    'week': 'week'
}

offense_renamed = offense.rename(columns=offense_cols)
defense_renamed = defense.rename(columns=defense_cols)

# Add prefix to avoid column collisions
offense_features = offense_renamed.copy()
for col in offense_features.columns:
    if col not in ['team', 'season', 'week']:
        offense_features.rename(columns={col: f'off_{col}'}, inplace=True)

defense_features = defense_renamed.copy()
for col in defense_features.columns:
    if col not in ['team', 'season', 'week']:
        defense_features.rename(columns={col: f'def_{col}'}, inplace=True)

# Merge on team + week
team_week = pd.merge(
    offense_features,
    defense_features,
    on=['team', 'season', 'week'],
    how='outer'
)

print(f"   ✅ Combined: {len(team_week)} team-weeks")
print(f"   📊 Features: {team_week.columns.size} columns\n")

# ============================================================================
# STEP 3: Add injury context (if available)
# ============================================================================

if not injuries.empty:
    print("💊 Adding injury impact scores...\n")
    
    injury_features = injuries[['team', 'week', 'injury_impact_score', 
                                'qb_injuries', 'out_count']].copy()
    injury_features.columns = ['team', 'week', 'injury_impact', 
                              'qb_out', 'players_out']
    
    team_week = pd.merge(
        team_week,
        injury_features,
        on=['team', 'week'],
        how='left'
    )
    
    # Fill NaN injury scores with 0 (no injuries)
    team_week['injury_impact'] = team_week['injury_impact'].fillna(0)
    team_week['qb_out'] = team_week['qb_out'].fillna(0).astype(int)
    team_week['players_out'] = team_week['players_out'].fillna(0).astype(int)
    
    print(f"   ✅ Added 3 injury features")
else:
    print("   ⚠️  No injury data to add\n")

# ============================================================================
# STEP 4: Calculate critical rolling windows & features
# ============================================================================

print("📈 Calculating Python-friendly rolling features...\n")

# Core EPA features (already in CSV, but ensure consistency)
epa_features = [
    'off_avg_epa_pass',
    'off_avg_epa_run', 
    'off_success_rate',
    'def_avg_epa_per_play',
    'def_success_rate_allowed'
]

# Rolling 3-game windows (from og_pipeline.R)
rolling_features = [
    'off_roll3_epa',
    'off_roll3_success_rate',
    'def_roll3_epa',
    'def_roll3_success_rate'
]

# Situational features
situational_features = [
    'off_third_down_rate',
    'off_red_zone_td_rate',
    'off_two_min_td_rate',
    'def_third_down_rate',
    'def_turnover_rate'
]

# Rename for Python consistency (match existing naming convention)
rename_map = {
    'off_roll3_epa': 'off_epa_l3',
    'off_roll3_success_rate': 'off_sr_l3',
    'def_roll3_epa': 'def_epa_l3',
    'def_roll3_success_rate': 'def_sr_l3'
}

for old_name, new_name in rename_map.items():
    if old_name in team_week.columns:
        team_week.rename(columns={old_name: new_name}, inplace=True)

print("   ✅ Rolling windows ready")
print(f"   ✅ {len([c for c in team_week.columns if 'epa' in c.lower()])} EPA features")
print(f"   ✅ {len([c for c in team_week.columns if 'third' in c.lower() or 'red_zone' in c.lower()])} situational features\n")

# ============================================================================
# STEP 5: Export to parquet
# ============================================================================

output_file = os.path.join(PROCESSED_DIR, "team_week_rich.parquet")

print(f"💾 Saving to: {output_file}\n")

# Convert numeric columns
numeric_cols = team_week.select_dtypes(include=[np.number]).columns
for col in numeric_cols:
    team_week[col] = pd.to_numeric(team_week[col], errors='coerce')

# Save
team_week.to_parquet(output_file, index=False, engine='pyarrow')

print("="*70)
print("   ✅ BRIDGE COMPLETE")
print("="*70)
print(f"\n📊 Summary:")
print(f"   • Rows: {len(team_week)}")
print(f"   • Columns: {team_week.columns.size}")
print(f"   • Output: {output_file}")
print(f"\n🎯 Next Steps:")
print(f"   1. python py/build_model_table_enhanced.py --season {SEASON}")
print(f"   2. python py/train_models_enhanced.py")
print(f"   3. python py/predict_week.py --season {SEASON} --week {WEEK + 1}\n")

# ============================================================================
# BONUS: Feature Summary
# ============================================================================

print("\n📋 Feature Summary:")
print("─" * 70)

feature_groups = {
    'EPA': [c for c in team_week.columns if 'epa' in c.lower()],
    'Success Rate': [c for c in team_week.columns if 'success' in c.lower()],
    'Situational': [c for c in team_week.columns if any(x in c.lower() for x in ['third', 'red_zone', 'two_min'])],
    'Pace': [c for c in team_week.columns if 'pace' in c.lower() or 'plays_per' in c.lower()],
    'Context': [c for c in team_week.columns if any(x in c.lower() for x in ['injury', 'rest', 'weather'])],
    'Rolling Windows': [c for c in team_week.columns if '_l3' in c.lower() or '_l6' in c.lower()]
}

for group_name, features in feature_groups.items():
    if features:
        print(f"\n{group_name} Features ({len(features)}):")
        for feat in features[:5]:  # Show first 5
            print(f"   • {feat}")
        if len(features) > 5:
            print(f"   ... and {len(features) - 5} more")

print("\n" + "="*70 + "\n")
