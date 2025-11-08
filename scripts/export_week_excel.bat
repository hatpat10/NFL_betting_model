@echo off
cd /d %~dp0\..
call .\.venv\Scripts\activate
set /p SEASON=Enter season (e.g., 2025): 
set /p WEEK=Enter week (e.g., 10): 
python py\export_week_to_excel.py --season %SEASON% --week %WEEK%
echo.
echo Done. See the exports\ folder.
pause
