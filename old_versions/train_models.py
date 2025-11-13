import os
import numpy as np
import pandas as pd

from sklearn.model_selection import TimeSeriesSplit
from sklearn.metrics import mean_absolute_error
from xgboost import XGBRegressor
import joblib

MODEL_TABLE = "data/processed/model_table.parquet"
OUT_MODEL   = "db/margin_model.joblib"

if not os.path.exists(MODEL_TABLE):
    raise SystemExit("Missing data/processed/model_table.parquet. Run build_model_table.py first.")

df = pd.read_parquet(MODEL_TABLE).sort_values(["season","week"])

if "margin" not in df.columns:
    raise SystemExit("model_table missing 'margin'. Re-run build_model_table.py.")
before = len(df)
df = df[df["margin"].notna()].copy()
print(f"Filtered rows with known margin: {len(df)}/{before}")

feature_cols = [c for c in df.columns if c.startswith(("delta_", "rating_", "ctx_"))]
if not feature_cols:
    feature_cols = [c for c in ["delta_off_epa_l6","delta_off_sr_l6","delta_off_epa","delta_off_sr","delta_plays"] if c in df.columns]
if not feature_cols:
    raise SystemExit("No usable feature columns found.")

X = df[feature_cols].apply(pd.to_numeric, errors="coerce").replace([np.inf, -np.inf], np.nan)
y = pd.to_numeric(df["margin"], errors="coerce")

mask = X.notna().all(axis=1) & y.notna()
drop_ct = int((~mask).sum())
if drop_ct:
    print(f"Dropping {drop_ct} rows with NaNs/Infs in features or label.")
X = X[mask].values
y = y[mask].values

n = len(y)
if n < 100:
    print(f"Warning: only {n} samples after cleaning; expect noisy CV.")
n_splits = 5 if n >= 500 else max(2, min(4, n // 50))
print(f"Using TimeSeriesSplit n_splits={n_splits}")

tscv = TimeSeriesSplit(n_splits=n_splits)
maes = []
for tr, te in tscv.split(X):
    m = XGBRegressor(
        n_estimators=400,
        max_depth=5,
        learning_rate=0.05,
        subsample=0.9,
        colsample_bytree=0.9,
        reg_lambda=2.0,
        random_state=42,
        n_jobs=-1,
    )
    m.fit(X[tr], y[tr])
    pred = m.predict(X[te])
    maes.append(mean_absolute_error(y[te], pred))
print("CV MAE (margin):", float(np.mean(maes)))

final = XGBRegressor(
    n_estimators=400,
    max_depth=5,
    learning_rate=0.05,
    subsample=0.9,
    colsample_bytree=0.9,
    reg_lambda=2.0,
    random_state=42,
    n_jobs=-1,
)
final.fit(X, y)

os.makedirs(os.path.dirname(OUT_MODEL), exist_ok=True)
joblib.dump(final, OUT_MODEL)
print(f"Saved model to {OUT_MODEL}")
