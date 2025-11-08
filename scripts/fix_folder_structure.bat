@echo off
REM ============================================================================
REM Quick Fix: Reorganize Folders & Add Enhanced Scripts
REM ============================================================================
REM Run this from: C:\Users\Patsc\Documents\nfl_betting_model
REM ============================================================================

echo.
echo ========================================================================
echo   FIXING FOLDER STRUCTURE
echo ========================================================================
echo.

REM Navigate to project root
cd /d C:\Users\Patsc\Documents\nfl_betting_model

echo [1/6] Moving R/data to root level...
if exist R\data (
    if exist data (
        echo Merging R\data into existing data\ folder...
        xcopy R\data\* data\ /E /I /Y
        rmdir /S /Q R\data
    ) else (
        echo Moving R\data to data\...
        move R\data data
    )
    echo SUCCESS
) else (
    echo R\data not found - skipping
)

echo.
echo [2/6] Moving R/db to root level...
if exist R\db (
    if exist db (
        echo Merging R\db into existing db\ folder...
        xcopy R\db\* db\ /E /I /Y
        rmdir /S /Q R\db
    ) else (
        echo Moving R\db to db\...
        move R\db db
    )
    echo SUCCESS
) else (
    echo R\db not found - skipping
)

echo.
echo [3/6] Creating missing data subfolders...
mkdir data\raw 2>nul
mkdir data\processed 2>nul
mkdir data\legacy 2>nul
echo SUCCESS

echo.
echo [4/6] Creating missing db folder...
mkdir db 2>nul
echo SUCCESS

echo.
echo [5/6] Organizing Python scripts into subfolders...
mkdir py\data 2>nul
mkdir py\training 2>nul
mkdir py\prediction 2>nul
mkdir py\evaluation 2>nul
mkdir py\export 2>nul

REM Move Python files to organized structure
if exist py\build_model_table.py move py\build_model_table.py py\data\
if exist py\train_models.py move py\train_models.py py\training\
if exist py\predict_week.py move py\predict_week.py py\prediction\
if exist py\odds_snapshot.py move py\odds_snapshot.py py\prediction\
if exist py\line_movement_report.py move py\line_movement_report.py py\evaluation\
if exist py\export_week_to_excel.py move py\export_week_to_excel.py py\export\
echo SUCCESS

echo.
echo [6/6] Creating reports folder...
mkdir reports 2>nul
echo SUCCESS

echo.
echo ========================================================================
echo   FOLDER STRUCTURE FIXED!
echo ========================================================================
echo.
echo Current structure:
echo   nfl_betting_model\
echo   ├── data\          (moved from R\data)
echo   ├── db\            (moved from R\db)
echo   ├── py\            (organized into subfolders)
echo   ├── R\             (R scripts only)
echo   ├── scripts\       (batch files)
echo   ├── reports\       (NEW - for predictions)
echo   └── exports\       (existing)
echo.
echo Next steps:
echo   1. Download enhanced scripts from Claude
echo   2. Place them in correct folders
echo   3. Run complete setup
echo.
pause
