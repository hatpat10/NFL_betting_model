import argparse, os, sqlite3, pandas as pd

SCHED = "data/raw/schedules.parquet"
DB    = "db/nfl.sqlite"
REPORTS_DIR = "reports"

parser = argparse.ArgumentParser()
parser.add_argument("--season", type=int, required=True)
parser.add_argument("--week", type=int, required=True)
args = parser.parse_args()

if not os.path.exists(DB):
    raise SystemExit("Missing db/nfl.sqlite. Run py/odds_snapshot.py first.")
if not os.path.exists(SCHED):
    raise SystemExit("Missing data/raw/schedules.parquet. Run R/01_ingest_historical.R first.")

sched = pd.read_parquet(SCHED)
if "game_type" in sched.columns:
    sched = sched[sched["game_type"].fillna("").str.upper().isin(["REG","REGULAR","REGULAR_SEASON",""])]
sched_wk = sched[(sched["season"]==args.season) & (sched["week"]==args.week)].copy()
if sched_wk.empty:
    raise SystemExit(f"No schedule rows for season={args.season} week={args.week}")

con = sqlite3.connect(DB)
snap = pd.read_sql_query("SELECT * FROM odds_snapshots", con)
con.close()
if snap.empty:
    raise SystemExit("No odds snapshots found. Run py/odds_snapshot.py.")

for col in ["ts_utc", "commence_time"]:
    if col in snap.columns:
        snap[col] = pd.to_datetime(snap[col], utc=True, errors="coerce")

wk_keys = sched_wk[["home_team","away_team"]].drop_duplicates()
snap = snap.merge(wk_keys, on=["home_team","away_team"], how="inner")

def summarize_market(df):
    df = df.sort_values("ts_utc")
    open_row = df.iloc[0]; close_row = df.iloc[-1]
    return pd.Series({
        "open_point": open_row.get("point"),
        "open_price": open_row.get("price"),
        "close_point": close_row.get("point"),
        "close_price": close_row.get("price"),
        "snapshots": len(df)
    })

grp_cols = ["event_id","home_team","away_team","commence_time","book","market","name"]
summary = snap.groupby(grp_cols, dropna=False).apply(summarize_market).reset_index()

summary = summary.merge(
    sched_wk[["season","week","home_team","away_team"]],
    on=["home_team","away_team"], how="left"
)

os.makedirs(REPORTS_DIR, exist_ok=True)
lm_csv = os.path.join(REPORTS_DIR, f"line_movement_week_{args.season}_{args.week}.csv")
summary.to_csv(lm_csv, index=False)
print(f"Wrote {lm_csv} with {len(summary)} rows.")

pred_path = os.path.join(REPORTS_DIR, f"week_{args.season}_{args.week}_predictions.csv")
if os.path.exists(pred_path):
    preds = pd.read_csv(pred_path)
    preds["model_home_spread"] = -preds["predicted_margin_home_minus_away"]
    home_spreads = summary[(summary["market"]=="spreads") & (summary["name"].eq(summary["home_team"]))].copy()
    merged = home_spreads.merge(
        preds[["home_team","away_team","model_home_spread"]],
        on=["home_team","away_team"], how="left"
    )
    merged["edge_home_spread_pts_vs_close"] = merged["model_home_spread"] - merged["close_point"]
    out_cols = ["season","week","home_team","away_team","book","open_point","close_point",
                "model_home_spread","edge_home_spread_pts_vs_close","snapshots","commence_time"]
    merged = merged[out_cols].sort_values(["home_team","away_team","book"])
    out_csv = os.path.join(REPORTS_DIR, f"line_movement_with_model_week_{args.season}_{args.week}.csv")
    merged.to_csv(out_csv, index=False)
    print(f"Wrote {out_csv} with {len(merged)} rows.")
else:
    print("No weekly predictions CSV found; skipped model edge merge.")
