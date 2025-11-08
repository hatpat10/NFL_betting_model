"""
Enhanced NFL Model Training - Uses ALL R-Engineered Features
=============================================================
Improvements over original train_models.py:
1. Uses 25+ features instead of just 5
2. Adds total points model (not just margin)
3. Comprehensive validation metrics (MAE, RMSE, R²)
4. Feature importance analysis
5. Saves both models + feature list
"""

import os
import numpy as np
import pandas as pd
from sklearn.model_selection import TimeSeriesSplit
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from xgboost import XGBRegressor
import joblib

# Paths
MODEL_TABLE = "data/processed/model_table.parquet"
OUT_DIR = "db"
MARGIN_MODEL = os.path.join(OUT_DIR, "margin_model.joblib")
TOTAL_MODEL = os.path.join(OUT_DIR, "total_model.joblib")
FEATURE_LIST = os.path.join(OUT_DIR, "feature_list.joblib")

print("\n" + "="*60)
print("  ENHANCED NFL MODEL TRAINING")
print("  Using Rich Features from R Pipeline")
print("="*60 + "\n")

# ============================================================================
# STEP 1: Load Data
# ============================================================================

if not os.path.exists(MODEL_TABLE):
    raise SystemExit(
        f"Missing {MODEL_TABLE}\n"
        "Run: Rscript export_features_to_python.R first"
    )

print("[1/7] Loading model table...")
df = pd.read_parquet(MODEL_TABLE).sort_values(["season", "week"])
print(f"   Loaded {len(df)} games from {df['season'].min()}-{df['season'].max()}")

# ============================================================================
# STEP 2: Filter to Completed Games
# ============================================================================

print("[2/7] Filtering to completed games with outcomes...")
before = len(df)
df = df[df["margin"].notna() & df["total_points"].notna()].copy()
print(f"   Kept {len(df)}/{before} completed games")

if len(df) < 100:
    raise SystemExit("Error: Insufficient training data (need 100+ games)")

# ============================================================================
# STEP 3: Select Features (Use ALL Available!)
# ============================================================================

print("[3/7] Selecting features...")

# Define feature categories
feature_patterns = [
    "delta_off_epa",      # Offensive EPA differentials (season + rolling)
    "delta_def_epa",      # Defensive EPA differentials
    "delta_off_sr",       # Success rate differentials
    "delta_def_sr",       # Defensive success rate
    "delta_off_third",    # 3rd down efficiency
    "delta_off_red",      # Red zone scoring
    "delta_explosive",    # Big play rate
    "delta_off_pass",     # Pass EPA differential
    "delta_off_rush",     # Rush EPA differential
    "delta_def_pass",     # Pass defense differential
    "delta_def_rush",     # Rush defense differential
    "projected_pace",     # Game pace projection
    "delta_pace",         # Pace differential
    "ctx_",               # Context features (weather, roof, etc.)
]

# Find all matching columns
feature_cols = []
for pattern in feature_patterns:
    matching = [c for c in df.columns if pattern in c]
    feature_cols.extend(matching)

# Remove duplicates and sort
feature_cols = sorted(set(feature_cols))

if not feature_cols:
    raise SystemExit("Error: No features found matching patterns")

print(f"   Selected {len(feature_cols)} features:")
print(f"   {', '.join(feature_cols[:5])} ... (showing first 5)")

# ============================================================================
# STEP 4: Prepare Training Data
# ============================================================================

print("[4/7] Preparing training matrices...")

# Features
X = df[feature_cols].apply(pd.to_numeric, errors="coerce")
X = X.replace([np.inf, -np.inf], np.nan)

# Labels
y_margin = pd.to_numeric(df["margin"], errors="coerce")
y_total = pd.to_numeric(df["total_points"], errors="coerce")

# Remove rows with NaN/Inf
mask = X.notna().all(axis=1) & y_margin.notna() & y_total.notna()
drop_ct = int((~mask).sum())

if drop_ct > 0:
    print(f"   Dropping {drop_ct} rows with missing/invalid values")

X = X[mask].values
y_margin = y_margin[mask].values
y_total = y_total[mask].values

print(f"   Training set: {len(y_margin)} games, {X.shape[1]} features")

# ============================================================================
# STEP 5: Train Margin Model with Cross-Validation
# ============================================================================

print("[5/7] Training MARGIN model with TimeSeriesSplit...")

n_samples = len(y_margin)
n_splits = 5 if n_samples >= 500 else max(2, min(4, n_samples // 100))
print(f"   Using {n_splits} time-series splits")

tscv = TimeSeriesSplit(n_splits=n_splits)

# Cross-validation
margin_maes = []
margin_rmses = []
margin_r2s = []

for fold, (train_idx, val_idx) in enumerate(tscv.split(X), 1):
    model = XGBRegressor(
        n_estimators=500,
        max_depth=5,
        learning_rate=0.03,
        subsample=0.85,
        colsample_bytree=0.85,
        reg_lambda=2.0,
        reg_alpha=1.0,
        random_state=42,
        n_jobs=-1,
    )
    
    model.fit(X[train_idx], y_margin[train_idx])
    preds = model.predict(X[val_idx])
    
    mae = mean_absolute_error(y_margin[val_idx], preds)
    rmse = np.sqrt(mean_squared_error(y_margin[val_idx], preds))
    r2 = r2_score(y_margin[val_idx], preds)
    
    margin_maes.append(mae)
    margin_rmses.append(rmse)
    margin_r2s.append(r2)
    
    print(f"   Fold {fold}: MAE={mae:.2f}, RMSE={rmse:.2f}, R²={r2:.3f}")

print(f"\n   Cross-Val MARGIN Results:")
print(f"   MAE:  {np.mean(margin_maes):.2f} ± {np.std(margin_maes):.2f} points")
print(f"   RMSE: {np.mean(margin_rmses):.2f} ± {np.std(margin_rmses):.2f} points")
print(f"   R²:   {np.mean(margin_r2s):.3f} ± {np.std(margin_r2s):.3f}")

# Train final model on all data
print("\n   Training final MARGIN model on full dataset...")
final_margin_model = XGBRegressor(
    n_estimators=500,
    max_depth=5,
    learning_rate=0.03,
    subsample=0.85,
    colsample_bytree=0.85,
    reg_lambda=2.0,
    reg_alpha=1.0,
    random_state=42,
    n_jobs=-1,
)
final_margin_model.fit(X, y_margin)

# ============================================================================
# STEP 6: Train Total Points Model
# ============================================================================

print("\n[6/7] Training TOTAL POINTS model...")

total_maes = []
total_rmses = []

for fold, (train_idx, val_idx) in enumerate(tscv.split(X), 1):
    model = XGBRegressor(
        n_estimators=500,
        max_depth=5,
        learning_rate=0.03,
        subsample=0.85,
        colsample_bytree=0.85,
        reg_lambda=2.0,
        random_state=42,
        n_jobs=-1,
    )
    
    model.fit(X[train_idx], y_total[train_idx])
    preds = model.predict(X[val_idx])
    
    mae = mean_absolute_error(y_total[val_idx], preds)
    rmse = np.sqrt(mean_squared_error(y_total[val_idx], preds))
    
    total_maes.append(mae)
    total_rmses.append(rmse)
    
    print(f"   Fold {fold}: MAE={mae:.2f}, RMSE={rmse:.2f}")

print(f"\n   Cross-Val TOTAL Results:")
print(f"   MAE:  {np.mean(total_maes):.2f} ± {np.std(total_maes):.2f} points")
print(f"   RMSE: {np.mean(total_rmses):.2f} ± {np.std(total_rmses):.2f} points")

# Train final total model
print("\n   Training final TOTAL model on full dataset...")
final_total_model = XGBRegressor(
    n_estimators=500,
    max_depth=5,
    learning_rate=0.03,
    subsample=0.85,
    colsample_bytree=0.85,
    reg_lambda=2.0,
    random_state=42,
    n_jobs=-1,
)
final_total_model.fit(X, y_total)

# ============================================================================
# STEP 7: Save Models and Feature Importance
# ============================================================================

print("\n[7/7] Saving models and analyzing features...")

os.makedirs(OUT_DIR, exist_ok=True)

# Save models
joblib.dump(final_margin_model, MARGIN_MODEL)
joblib.dump(final_total_model, TOTAL_MODEL)
joblib.dump(feature_cols, FEATURE_LIST)

print(f"   ✓ Saved: {MARGIN_MODEL}")
print(f"   ✓ Saved: {TOTAL_MODEL}")
print(f"   ✓ Saved: {FEATURE_LIST}")

# Feature importance
importance_df = pd.DataFrame({
    'feature': feature_cols,
    'importance': final_margin_model.feature_importances_
}).sort_values('importance', ascending=False)

print("\n   Top 15 Most Important Features (for MARGIN):")
for idx, row in importance_df.head(15).iterrows():
    print(f"   {row['feature']:30s} {row['importance']:.4f}")

# Save importance
importance_path = os.path.join(OUT_DIR, "feature_importance.csv")
importance_df.to_csv(importance_path, index=False)
print(f"\n   ✓ Saved: {importance_path}")

# ============================================================================
# SUMMARY
# ============================================================================

print("\n" + "="*60)
print("  TRAINING COMPLETE")
print("="*60)
print(f"\n📊 MODEL PERFORMANCE:")
print(f"   Margin MAE:  {np.mean(margin_maes):.2f} points")
print(f"   Total MAE:   {np.mean(total_maes):.2f} points")
print(f"   Features:    {len(feature_cols)}")
print(f"   Training:    {len(y_margin)} games")
print(f"\n💾 OUTPUTS:")
print(f"   • {MARGIN_MODEL}")
print(f"   • {TOTAL_MODEL}")
print(f"   • {FEATURE_LIST}")
print(f"   • {importance_path}")
print(f"\n🎯 NEXT STEPS:")
print(f"   1. Review feature importance in {importance_path}")
print(f"   2. Run predictions: python predict_week_enhanced.py --season 2025 --week 9")
print(f"   3. Run backtest: python backtest_enhanced.py")
print()
