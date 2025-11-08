@echo off
cd /d %~dp0\..
python -m venv .venv
call .\.venv\Scripts\activate
pip install -r py\requirements.txt
echo.
echo === Python environment ready.
echo Next:
echo   - In RStudio run: R/01_ingest_historical.R and R/02_features_team_week.R
echo   - Then:
echo       .\.venv\Scripts\activate
echo       python py\build_model_table.py
echo       python py\train_models.py
pause
