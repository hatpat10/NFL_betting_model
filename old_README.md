# NFL Betting Model Starter

This bundle contains a minimal, working scaffold for an NFL pre-game model using:
- **R (nflverse)** for schedules and play-by-play and rolling features
- **Python** for odds snapshots, model training, predictions, line-movement reporting
- **Excel export** for manual analysis

## Quick Start (Windows)
1) Open Command Prompt in this folder, then:
```
python -m venv .venv
.\.venv\Scriptsctivate
pip install -r py\requirements.txt
```
2) Copy `config\.env.sample` → `config\.env` and set your Odds API key.
3) In RStudio, run:
   - `R/01_ingest_historical.R`
   - `R/02_features_team_week.R`
4) Build & train:
```
python py\build_model_table.py
python py\train_models.py
```
5) Predict a week:
```
python py\predict_week.py --season 2025 --week 10
```
6) (Optional) Line movement & Excel export:
```
python py\odds_snapshot.py
python py\line_movement_report.py --season 2025 --week 10
python py\export_week_to_excel.py --season 2025 --week 10
```
"# NFL_betting_model" 
