"""
NFL Betting Model - Enhanced Training Script
=============================================
Trains XGBoost models on rich features from og_pipeline.R

Input:  data/processed/model_table_rich.parquet
Output: db/margin_model_rich.joblib
        db/total_model_rich.joblib
        db/feature_importance.csv

Features: 20+ rich features including:
- EPA (pass/run splits, rolling windows)
- Success rates
- Situational stats (3rd down, red zone, 2-min)
- Pace of play
- Context (injuries, rest)

Usage:
    python train_models_enhanced.py
"""

import os
import numpy as np
import pandas as pd
from sklearn.model_selection import TimeSeriesSplit
from sklearn.metrics import mean_absolute_error, log_loss
from xgboost import XGBRegressor, XGBClassifier
import joblib

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
FEATURE_IMPORTANCE = os.path.join(REPORTS_DIR, "feature_importance_rich.csv")

os.makedirs(MODEL_DIR, exist_ok=True)
os.makedirs(REPORTS_DIR, exist_ok=True)

print("\n" + "="*70)
print("   🤖 TRAINING ENHANCED NFL BETTING MODELS")
print("="*70 + "\n")

# ============================================================================
# STEP 1: Load data
# ============================================================================

print("[1/6] Loading model table...")
if not os.path.exists(MODEL_TABLE):
    raise FileNotFoundError(
        f"❌ Missing {MODEL_TABLE}\n"
        f"   Run: python build_model_table_enhanced.py --season 2025"
    )

df = pd.read_parquet(MODEL_TABLE).sort_values(["season", "week"])
print(f"   ✅ Loaded {len(df)} games\n")

# ============================================================================
# STEP 2: Select features
# ============================================================================

print("[2/6] Selecting features...")

# Start with delta features (matchup context)
delta_features = [c for c in df.columns if c.startswith("delta_")]

# Add home advantages if available
home_context = []
if "home_injury_impact" in df.columns:
    home_context.append("home_injury_impact")
if "away_injury_impact" in df.columns:
    home_context.append("away_injury_impact")

# Combine all features
feature_cols = delta_features + home_context

print(f"   📊 Selected {len(feature_cols)} features:")
print(f"      • Delta (matchup): {len(delta_features)}")
print(f"      • Context: {len(home_context)}")

if len(feature_cols) < 5:
    print("\n   ⚠️  WARNING: Very few features available!")
    print("      Consider running bridge_og_to_python.py with more weeks\n")

# Show top features
print(f"\n   🔝 Top features (first 10):")
for feat in feature_cols[:10]:
    print(f"      • {feat}")
if len(feature_cols) > 10:
    print(f"      ... and {len(feature_cols) - 10} more\n")

# ============================================================================
# STEP 3: Prepare training data
# ============================================================================

print("[3/6] Preparing training data...")

# Filter to games with known results
before = len(df)
df_train = df[df["margin"].notna()].copy()
print(f"   ✅ {len(df_train)}/{before} games with results (targets)")

if len(df_train) < 100:
    print(f"\n   ⚠️  WARNING: Only {len(df_train)} training samples!")
    print("      Models may be noisy. Recommend 200+ games for reliable training.\n")

# Extract features and targets
X = df_train[feature_cols].apply(pd.to_numeric, errors='coerce').replace([np.inf, -np.inf], np.nan)
y_margin = pd.to_numeric(df_train["margin"], errors='coerce')
y_total = pd.to_numeric(df_train["total_points"], errors='coerce')

# Drop rows with NaN
mask_margin = X.notna().all(axis=1) & y_margin.notna()
mask_total = X.notna().all(axis=1) & y_total.notna()

drop_ct_margin = int((~mask_margin).sum())
drop_ct_total = int((~mask_total).sum())

if drop_ct_margin > 0:
    print(f"   🧹 Dropping {drop_ct_margin} rows with NaN (margin)")
if drop_ct_total > 0:
    print(f"   🧹 Dropping {drop_ct_total} rows with NaN (total)")

X_margin = X[mask_margin].values
y_margin = y_margin[mask_margin].values
X_total = X[mask_total].values
y_total = y_total[mask_total].values

print(f"\n   Final training samples:")
print(f"      • Margin model: {len(y_margin)}")
print(f"      • Total model: {len(y_total)}\n")

# ============================================================================
# STEP 4: Time-series cross-validation
# ============================================================================

print("[4/6] Running time-series cross-validation...")

n = len(y_margin)
n_splits = 5 if n >= 500 else max(2, min(4, n // 50))
print(f"   📊 Using TimeSeriesSplit with {n_splits} splits\n")

tscv = TimeSeriesSplit(n_splits=n_splits)

# ─────────────────────────────────────────────────────────────────────────
# Train Margin Model
# ─────────────────────────────────────────────────────────────────────────

print("   🎯 Training Margin Model (home_score - away_score)...")

margin_maes = []
for fold_idx, (tr, te) in enumerate(tscv.split(X_margin), 1):
    m = XGBRegressor(
        n_estimators=400,
        max_depth=5,
        learning_rate=0.05,
        subsample=0.9,
        colsample_bytree=0.9,
        reg_lambda=2.0,
        random_state=42,
        n_jobs=-1,
        verbosity=0
    )
    m.fit(X_margin[tr], y_margin[tr])
    pred = m.predict(X_margin[te])
    mae = mean_absolute_error(y_margin[te], pred)
    margin_maes.append(mae)
    print(f"      Fold {fold_idx}: MAE = {mae:.2f} pts")

avg_margin_mae = float(np.mean(margin_maes))
print(f"   ✅ CV MAE (Margin): {avg_margin_mae:.2f} points\n")

# ─────────────────────────────────────────────────────────────────────────
# Train Total Model
# ─────────────────────────────────────────────────────────────────────────

print("   🎯 Training Total Model (home_score + away_score)...")

total_maes = []
for fold_idx, (tr, te) in enumerate(tscv.split(X_total), 1):
    m = XGBRegressor(
        n_estimators=400,
        max_depth=5,
        learning_rate=0.05,
        subsample=0.9,
        colsample_bytree=0.9,
        reg_lambda=2.0,
        random_state=42,
        n_jobs=-1,
        verbosity=0
    )
    m.fit(X_total[tr], y_total[tr])
    pred = m.predict(X_total[te])
    mae = mean_absolute_error(y_total[te], pred)
    total_maes.append(mae)
    print(f"      Fold {fold_idx}: MAE = {mae:.2f} pts")

avg_total_mae = float(np.mean(total_maes))
print(f"   ✅ CV MAE (Total): {avg_total_mae:.2f} points\n")

# ============================================================================
# STEP 5: Train final models on all data
# ============================================================================

print("[5/6] Training final models on full dataset...")

# Final Margin Model
margin_model = XGBRegressor(
    n_estimators=400,
    max_depth=5,
    learning_rate=0.05,
    subsample=0.9,
    colsample_bytree=0.9,
    reg_lambda=2.0,
    random_state=42,
    n_jobs=-1,
    verbosity=0
)
margin_model.fit(X_margin, y_margin)
joblib.dump(margin_model, MARGIN_MODEL)
print(f"   ✅ Saved: {MARGIN_MODEL}")

# Final Total Model
total_model = XGBRegressor(
    n_estimators=400,
    max_depth=5,
    learning_rate=0.05,
    subsample=0.9,
    colsample_bytree=0.9,
    reg_lambda=2.0,
    random_state=42,
    n_jobs=-1,
    verbosity=0
)
total_model.fit(X_total, y_total)
joblib.dump(total_model, TOTAL_MODEL)
print(f"   ✅ Saved: {TOTAL_MODEL}\n")

# ============================================================================
# STEP 6: Feature importance
# ============================================================================

print("[6/6] Analyzing feature importance...")

# Get importance from margin model
importance_df = pd.DataFrame({
    'feature': feature_cols,
    'importance_margin': margin_model.feature_importances_,
    'importance_total': total_model.feature_importances_
})

importance_df['importance_avg'] = (
    importance_df['importance_margin'] + importance_df['importance_total']
) / 2

importance_df = importance_df.sort_values('importance_avg', ascending=False)
importance_df.to_csv(FEATURE_IMPORTANCE, index=False)

print(f"   ✅ Saved: {FEATURE_IMPORTANCE}\n")

print("   🏆 Top 10 Most Important Features:")
print("   " + "─" * 66)
for idx, row in importance_df.head(10).iterrows():
    print(f"   {row['feature']:40s} {row['importance_avg']:.4f}")

print("\n" + "="*70)
print("   ✅ TRAINING COMPLETE")
print("="*70)
print(f"\n📊 Model Performance:")
print(f"   • Margin MAE: {avg_margin_mae:.2f} points")
print(f"   • Total MAE:  {avg_total_mae:.2f} points")

print(f"\n💾 Saved Models:")
print(f"   • {MARGIN_MODEL}")
print(f"   • {TOTAL_MODEL}")
print(f"   • {FEATURE_IMPORTANCE}")

print(f"\n🎯 Next Steps:")
print(f"   python py/predict_week_enhanced.py --season 2025 --week 10\n")
