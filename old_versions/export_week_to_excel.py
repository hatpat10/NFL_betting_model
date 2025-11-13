import argparse, os, pandas as pd, sqlite3

SCHED   = "data/raw/schedules.parquet"
TEAMW   = "data/processed/team_week.parquet"
MODELT  = "data/processed/model_table.parquet"
DBPATH  = "db/nfl.sqlite"
REPORTS = "reports"
EXPORTS = "exports"

parser = argparse.ArgumentParser()
parser.add_argument("--season", type=int, required=True)
parser.add_argument("--week", type=int, required=True)
args = parser.parse_args()

os.makedirs(EXPORTS, exist_ok=True)

if not os.path.exists(SCHED) or not os.path.exists(TEAMW):
    raise SystemExit("Missing schedules or team_week parquet. Run R scripts first.")

sched = pd.read_parquet(SCHED)
if "game_type" in sched.columns:
    sched = sched[sched["game_type"].fillna("").str.upper().isin(["REG","REGULAR","REGULAR_SEASON",""])]
sched_wk = sched[(sched["season"]==args.season) & (sched["week"]==args.week)].copy()
if sched_wk.empty:
    raise SystemExit(f"No schedule rows for season={args.season} week={args.week}")

tw = pd.read_parquet(TEAMW)
teams = pd.unique(pd.concat([sched_wk["home_team"], sched_wk["away_team"]], ignore_index=True))
tw_slice = tw[tw["team"].isin(teams)].copy()

model_slice = None
if os.path.exists(MODELT):
    mt = pd.read_parquet(MODELT)
    model_slice = mt[(mt["season"]==args.season) & (mt["week"]==args.week)].copy()

odds_summary = None
if os.path.exists(DBPATH):
    con = sqlite3.connect(DBPATH)
    try:
        snap = pd.read_sql_query("SELECT * FROM odds_snapshots", con)
    except Exception:
        snap = pd.DataFrame()
    finally:
        con.close()
    if not snap.empty:
        snap["ts_utc"] = pd.to_datetime(snap["ts_utc"], utc=True, errors="coerce")
        def summarize(df):
            df = df.sort_values("ts_utc")
            open_row = df.iloc[0]; close_row = df.iloc[-1]
            return pd.Series({
                "open_point": open_row.get("point"),
                "open_price": open_row.get("price"),
                "close_point": close_row.get("point"),
                "close_price": close_row.get("price"),
                "snapshots": len(df)
            })
        keys = ["event_id","home_team","away_team","commence_time","book","market","name"]
        summary = snap.groupby(keys, dropna=False).apply(summarize).reset_index()
        odds_summary = summary.merge(
            sched_wk[["home_team","away_team"]],
            on=["home_team","away_team"], how="inner"
        )
    else:
        odds_summary = pd.DataFrame()

pred_path = os.path.join(REPORTS, f"week_{args.season}_{args.week}_predictions.csv")
preds = pd.read_csv(pred_path) if os.path.exists(pred_path) else pd.DataFrame()

out_xlsx = os.path.join(EXPORTS, f"week_{args.season}_{args.week}_model_data.xlsx")
with pd.ExcelWriter(out_xlsx, engine="openpyxl") as xl:
    sched_wk.to_excel(xl, sheet_name="schedule_week", index=False)
    tw_slice.to_excel(xl, sheet_name="team_week_features", index=False)
    if model_slice is not None and not model_slice.empty:
        model_slice.to_excel(xl, sheet_name="model_table_slice", index=False)
    if odds_summary is not None and not odds_summary.empty:
        odds_summary.to_excel(xl, sheet_name="odds_summary", index=False)
    if not preds.empty:
        preds.to_excel(xl, sheet_name="predictions", index=False)

print(f"Wrote {out_xlsx}")
