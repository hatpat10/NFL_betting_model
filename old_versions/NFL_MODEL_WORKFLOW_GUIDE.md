# NFL BETTING MODEL - COMPLETE WORKFLOW GUIDE
# ============================================================================

## INITIAL SETUP (One-Time Only)

### 1. Directory Structure
Your project should be organized like this:
```
C:\Users\Patsc\Documents\NFL_betting_model\
├── config\
│   ├── .env          # Your API keys (private - don't share!)
│   └── .env.sample   # Template for others
├── data\
│   ├── raw\          # Raw data files
│   └── processed\    # Processed data files
├── db\               # SQLite databases
├── models\           # Trained models
├── reports\          # Output CSV files and reports
├── R\                # R scripts
└── py\               # Python scripts
```

### 2. Environment File Setup
Add your API keys to `config\.env`:
```
# The Odds API (for current/future games)
ODDS_API_KEY=a35f7d5b7f91dbca7a9364b72c1b1cf2

# SportsData.io (for historical odds)
SPORTSDATA_API_KEY=your_sportsdata_key_here

# Optional: Database paths
DB_PATH=db/nfl_odds.sqlite
```

## WEEKLY WORKFLOW (Every Week During NFL Season)

### Step 1: Open Terminal/Command Prompt
```bash
# Navigate to your project directory
cd C:\Users\Patsc\Documents\NFL_betting_model

# Verify you're in the right place
dir
```

### Step 2: Update Data (Monday/Tuesday)
```r
# In R console or RStudio
setwd("C:/Users/Patsc/Documents/NFL_betting_model")

# Load the latest NFL data
source("R/01_update_nfl_data.R")

# This fetches:
# - Latest game results
# - Updated team stats
# - Player data
```

### Step 3: Fetch Historical Odds (For Backtesting)
```r
# Get historical odds for completed weeks
source("fetch_2025_odds_with_env.R")

# This automatically:
# - Loads your .env file
# - Fetches odds from SportsData.io
# - Stores in db/nfl_odds_2025.sqlite
```

### Step 4: Generate Predictions (Wednesday/Thursday)
```r
# Set the week you want to predict
CURRENT_WEEK <- 11  # Update this each week
SEASON <- 2025

# Run your prediction model
source("R/generate_predictions.R")

# Or if using Python model:
# system("python py/predict_week.py 2025 11")
```

### Step 5: Fetch Current Odds (Thursday/Friday)
```r
# Get current betting lines for upcoming games
source("R/fetch_current_odds.R")

# This uses The Odds API for current week
```

### Step 6: Find Betting Edges
```r
# Compare your predictions to Vegas lines
source("R/find_edges.R")

# This outputs:
# - reports/week_11_edges.csv
# - Games where model disagrees with Vegas by 2+ points
```

### Step 7: Backtest Previous Weeks (Optional)
```r
# Evaluate how your model performed
source("backtest_2025_weeks_5_10.R")

# Shows:
# - ATS win rate
# - Accuracy by edge size
# - Weekly performance
```

## GAME DAY WORKFLOW (Sunday)

### Morning Update (Optional)
```r
# Get latest line movements
source("R/line_movement_check.R")

# Check for:
# - Significant line moves
# - Injury updates
# - Weather changes
```

### Post-Game Analysis (Sunday Night/Monday)
```r
# After games complete
source("R/evaluate_week.R")

# Records:
# - Actual results vs predictions
# - Which bets won/lost
# - Updates performance tracking
```

## PYTHON ALTERNATIVE WORKFLOW

If you prefer Python for some tasks:

```bash
# In terminal
cd C:\Users\Patsc\Documents\NFL_betting_model

# Activate virtual environment (if using one)
python -m venv venv
venv\Scripts\activate

# Install requirements (first time only)
pip install -r requirements.txt

# Fetch odds
python py/fetch_sportsdata_odds.py 2025 10

# Generate predictions
python py/predict_week.py 2025 11

# Export to Excel
python py/export_week_to_excel.py 2025 11
```

## QUICK REFERENCE COMMANDS

### Terminal Navigation
```bash
# Go to project
cd C:\Users\Patsc\Documents\NFL_betting_model

# List files
dir

# Check current directory
echo %cd%

# Go back one directory
cd ..
```

### R Commands
```r
# Set working directory
setwd("C:/Users/Patsc/Documents/NFL_betting_model")

# Check working directory
getwd()

# List files
list.files()

# Install packages (if needed)
install.packages(c("tidyverse", "nflreadr", "httr"))

# Load packages
library(tidyverse)
library(nflreadr)
```

### Environment Check
```r
# Verify .env is loaded
source("load_env.R")
load_dot_env("config/.env")

# Check if API keys are set
Sys.getenv("SPORTSDATA_API_KEY")
Sys.getenv("ODDS_API_KEY")
```

## TROUBLESHOOTING

### Issue: "API key not found"
```r
# Manually load .env
source("load_env.R")
load_dot_env("config/.env")
```

### Issue: "No such file or directory"
```r
# Check you're in right directory
getwd()
# Should show: "C:/Users/Patsc/Documents/NFL_betting_model"

# If not, navigate there:
setwd("C:/Users/Patsc/Documents/NFL_betting_model")
```

### Issue: "Package not installed"
```r
# Install missing packages
install.packages("package_name")

# For NFL data:
install.packages("nflreadr")
install.packages("nflfastR")
```

### Issue: Database locked
```r
# Close all connections
DBI::dbDisconnect(con)

# Or restart R session:
# RStudio: Session -> Restart R
```

## WEEKLY CHECKLIST

□ Monday
  - [ ] Update NFL data (scores, stats)
  - [ ] Fetch historical odds for last week
  - [ ] Run backtest on last week's predictions

□ Tuesday/Wednesday  
  - [ ] Generate features for upcoming week
  - [ ] Train/update models if needed
  
□ Thursday
  - [ ] Generate predictions for all games
  - [ ] Fetch current betting lines
  - [ ] Identify edges (model vs Vegas)
  
□ Friday
  - [ ] Final odds check
  - [ ] Export predictions to CSV/Excel
  - [ ] Review high-confidence plays
  
□ Sunday
  - [ ] Morning: Check for line moves/injuries
  - [ ] Evening: Record actual results
  
□ Monday (next week)
  - [ ] Evaluate performance
  - [ ] Update tracking spreadsheet
  - [ ] Adjust model if needed

## FILE NAMING CONVENTIONS

```
# Predictions
reports/week_2025_11_predictions.csv

# Odds
reports/consensus_odds_2025_week_11.csv

# Edges
reports/betting_edges_2025_week_11.csv

# Backtest
reports/backtest_results_2025_weeks_5_10.csv
```

## IMPORTANT NOTES

1. **Never commit .env to Git** - It contains private API keys
2. **Run scripts from project root** - Not from subdirectories
3. **Update week numbers** - Change CURRENT_WEEK variable each week
4. **Check data freshness** - NFL data updates Tuesday mornings
5. **Save outputs** - Keep weekly reports for season-long tracking

## SAMPLE WEEKLY SCRIPT

Create a file `run_weekly_analysis.R`:

```r
# Weekly NFL Betting Model Run
# Update CURRENT_WEEK before running

CURRENT_WEEK <- 11
SEASON <- 2025

# Load environment
source("load_env.R")
load_dot_env("config/.env")

# Update data
source("R/01_update_nfl_data.R")

# Generate predictions
source("R/generate_predictions.R")

# Fetch current odds
source("R/fetch_current_odds.R")

# Find edges
source("R/find_edges.R")

# Print summary
cat("\n======================\n")
cat("Week", CURRENT_WEEK, "Analysis Complete\n")
cat("Check reports/ folder for:\n")
cat("- Predictions\n")
cat("- Betting edges\n")
cat("- Consensus odds\n")
cat("======================\n")
```

Then just run: `source("run_weekly_analysis.R")`

## QUESTIONS?

If you need help with any step, the key files are:
- `fetch_2025_odds_with_env.R` - Gets historical odds
- `backtest_2025_weeks_5_10.R` - Tests model accuracy
- `load_env.R` - Manages environment variables
- Your prediction scripts in `R/` folder

Remember: The .env file stays in `config/.env` and is automatically loaded by the scripts!
