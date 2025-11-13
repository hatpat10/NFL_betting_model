# 🏈 NFL Betting Model - Data-Driven NFL Predictions

[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](https://choosealicense.com/licenses/mit/)
[![R](https://img.shields.io/badge/R-4.0+-blue.svg)](https://www.r-project.org/)
[![Status](https://img.shields.io/badge/Status-Production-success.svg)]()

> **A comprehensive pre-game NFL prediction model that identifies betting edges by comparing advanced analytics against sportsbook lines.**

Transform play-by-play data into profitable predictions using EPA (Expected Points Added), rolling averages, situational adjustments, and real-time odds integration.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Project Structure](#project-structure)
- [How It Works](#how-it-works)
- [Weekly Workflow](#weekly-workflow)
- [Output Files](#output-files)
- [Configuration](#configuration)
- [API Requirements](#api-requirements)
- [Model Methodology](#model-methodology)
- [Performance Tracking](#performance-tracking)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Disclaimer](#disclaimer)
- [License](#license)

---

## 🎯 Overview

This NFL betting model:

- **Predicts game outcomes** with point spreads and win probabilities
- **Identifies value bets** by comparing model predictions vs Vegas lines
- **Uses advanced metrics** including EPA, success rate, and explosiveness
- **Incorporates context** like weather, injuries, rest, and travel
- **Provides actionable insights** with confidence tiers and edge calculations
- **Tracks historical performance** using SQLite database (2021-2025)

### What Makes This Model Different?

✅ **Data-driven:** Uses nflfastR play-by-play data (not just box scores)  
✅ **Rolling metrics:** 3-game and 5-game windows capture recent form  
✅ **Situational awareness:** Accounts for weather, injuries, rest, HFA  
✅ **Real-time integration:** Fetches live odds from The Odds API  
✅ **Transparent:** Shows edge calculations and confidence levels  
✅ **Production-ready:** Runs weekly with reproducible results  

---

## ✨ Features

### Core Capabilities

- **🎲 Spread Predictions:** Predicted point margin (home vs away)
- **🏆 Win Probability:** Likelihood each team wins (0-100%)
- **📊 Total Points:** Over/Under projections
- **💰 Betting Edges:** Model line vs Vegas line comparison
- **🎯 Confidence Tiers:** Very High, High, Medium, Low, Very Low
- **📈 EV Classification:** Elite (🔥), Strong (⭐), Good (✓), Pass (⛔)

### Advanced Analytics

- **EPA (Expected Points Added):** Measures play efficiency
- **Success Rate:** Percentage of "successful" plays
- **Explosiveness:** Big play frequency (20+ yd passes, 10+ yd runs)
- **Red Zone Efficiency:** TD rate inside the 20
- **Third Down Conversions:** Critical situation performance
- **Turnover Rates:** Ball security and takeaway metrics

### Contextual Adjustments

- **🏟️ Home Field Advantage:** 2.5 point baseline
- **😴 Rest Differential:** 0.5 points per day advantage
- **✈️ Travel Distance:** Penalties for long/cross-country trips
- **⛈️ Weather Impact:** Temperature, wind, precipitation effects
- **🤕 Injury Analysis:** Key player and QB availability
- **📅 Division Games:** Rivalry adjustments

---

## 🚀 Quick Start

### Prerequisites

- R (version 4.0+)
- RStudio (recommended)
- API keys (see [API Requirements](#api-requirements))

### 5-Minute Setup

```r
# 1. Clone the repository
git clone https://github.com/hatpat10/NFL_betting_model.git
cd NFL_betting_model

# 2. Install required packages
source("packs.R")

# 3. Set up API keys (see Configuration section)
# Edit config/.env with your keys

# 4. Run the pipeline
source("pipeline_db_21_25.R")

# 5. Get odds and betting edges
source("og_odds.R")
```

**First run takes ~5 minutes** (downloads and processes historical data)  
**Subsequent runs take ~2 minutes** (uses cached database)

---

## 📥 Installation

### Step 1: Install R and RStudio

**Windows:**
1. Download R from [CRAN](https://cran.r-project.org/bin/windows/base/)
2. Download RStudio from [Posit](https://posit.co/download/rstudio-desktop/)

**Mac:**
1. Download R from [CRAN](https://cran.r-project.org/bin/macosx/)
2. Download RStudio from [Posit](https://posit.co/download/rstudio-desktop/)

### Step 2: Clone Repository

```bash
git clone https://github.com/hatpat10/NFL_betting_model.git
cd NFL_betting_model
```

### Step 3: Install R Packages

**Option A - Automatic (Recommended):**
```r
source("packs.R")
```

**Option B - Manual:**
```r
install.packages(c(
  "nflverse", "nflreadr", "nflfastR", "nflplotR",
  "dplyr", "tidyr", "lubridate", "zoo",
  "DBI", "RSQLite", "dbplyr",
  "httr", "jsonlite", "writexl", "ggplot2"
))
```

### Step 4: Set Up API Keys

Create `config/.env` file:

```bash
ODDS_API_KEY=your_odds_api_key_here
SPORTSDATA_API_KEY=your_sportsdata_key_here
WEATHER_API_KEY=your_weather_key_here
```

**Get API Keys:**
- **Odds API:** [https://the-odds-api.com/](https://the-odds-api.com/) (500 free requests/month)
- **SportsData.io:** [https://sportsdata.io/](https://sportsdata.io/) (free tier available)
- **Weather API:** [https://www.weatherapi.com/](https://www.weatherapi.com/) (optional)

### Step 5: Set Base Directory

Edit `pipeline_db_21_25.R` line 18:
```r
BASE_DIR <- "C:/Users/YourName/Documents/NFL_betting_model"  # Update this path
```

---

## 📁 Project Structure

```
NFL_betting_model/
│
├── README.md                           # This file
├── WEEKLY_WORKFLOW_CHECKLIST.md        # Weekly operations guide
├── NFL_MODEL_WORKFLOW_GUIDE.md         # Detailed methodology
│
├── 📊 Core Scripts
├── pipeline_db_21_25.R                 # Main prediction engine
├── og_odds.R                           # Odds integration & edge finder
├── packs.R                             # Package installer
│
├── 🔧 Utilities
├── sportsdata_injuries.R               # Injury data fetcher
├── weather_fetcher.R                   # Weather data fetcher
├── utils.py                            # Python utilities (optional)
│
├── ⚙️ Configuration
├── config/
│   └── .env                            # API keys (DO NOT COMMIT)
│
├── 💾 Data
├── pbp_db_2021_2025.sqlite            # Play-by-play database
├── weather_data.csv                    # Weather data (optional)
├── nfl_injuries.csv                    # Injury data (optional)
│
├── 📂 Outputs (Generated Weekly)
├── week11/                             # Changes each week
│   ├── Week_11_Model_Output.xlsx      # Main predictions
│   ├── matchup_analysis/
│   │   ├── betting_recommendations_enhanced.csv
│   │   └── matchup_summary_enhanced.csv
│   └── odds_analysis/
│       ├── betting_picks_week11.xlsx  # Betting recommendations
│       ├── profitable_bets.csv
│       ├── all_games_analysis.csv
│       └── betting_edges.png          # Visualization
│
└── 📚 Documentation
    ├── Building_an_NFL_Betting_Prediction_Model__A_Comprehensive_Outline.pdf
    ├── StepbyStep_Guide_to_Building_the_NFL_Betting_Model.pdf
    └── Data_Collection__Setup.pdf
```

---

## 🔬 How It Works

### The Pipeline (3 Phases)

```
┌─────────────────────────────────────────────────────────────┐
│  PHASE 1: Data Collection & Processing                     │
│  • Load nflfastR play-by-play data (2021-2025)            │
│  • Store in SQLite database                                 │
│  • Calculate play-level metrics (EPA, success, etc.)       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  PHASE 2: Feature Engineering                               │
│  • Aggregate to team-week level                            │
│  • Calculate rolling averages (3-game, 5-game)             │
│  • Compute trends and momentum                              │
│  • Add situational context (weather, injuries, rest)       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  PHASE 3: Prediction & Betting Analysis                    │
│  • Generate point spread predictions                        │
│  • Calculate win probabilities                              │
│  • Compare vs Vegas lines (via Odds API)                   │
│  • Identify edges and classify by EV tier                  │
└─────────────────────────────────────────────────────────────┘
```

### Key Calculations

**1. Predicted Margin Formula:**
```
predicted_margin = base_prediction - total_adjustments

where:
  base_prediction = (away_total_rating - home_total_rating) × 0.15
  
  total_adjustments = 
    + home_field_advantage (2.5 pts)
    + rest_differential × 0.5
    + travel_adjustment (-0.5 to -2.0 pts)
    + weather_adjustment (-0.5 to -2.0 pts)
    + division_game_adjustment (-1.0 pt)
    + injury_adjustment (variable)
    + momentum_adjustment (trend × 5)
```

**2. Team Ratings:**
```
offense_rating = (EPA × 20) + (Success Rate × 50) + (Explosiveness × 30)
defense_rating = -(Def EPA × 20) - (Def Success × 50) - (Def Explosive × 30) 
                 + (Turnovers Forced × 10)
total_rating = offense_rating + defense_rating
```

**3. Betting Edge:**
```
edge = model_spread - vegas_spread

Example:
  Model: BAL -2.2
  Vegas: CLE -7.5
  Edge: -9.7 points (bet BAL!)
```

**4. EV Tiers:**
```
🔥 ELITE:  |edge| ≥ 4.0 points
⭐ STRONG: |edge| ≥ 2.5 points
✓ GOOD:   |edge| ≥ 1.5 points
⛔ PASS:   |edge| < 1.5 points
```

---

## 📅 Weekly Workflow

### Monday Morning (5-10 minutes)

**1. Update Configuration**

Edit `pipeline_db_21_25.R` lines 14-16:
```r
CURRENT_SEASON <- 2025
CURRENT_WEEK <- 11      # Last completed week
PREDICTION_WEEK <- 12   # Week you're predicting
```

**2. Run Pipeline**
```r
source("C:/Users/YourName/Documents/NFL_betting_model/pipeline_db_21_25.R")
```

**3. Fetch Odds**

Edit `og_odds.R` line 18:
```r
WEEK <- 12  # Must match PREDICTION_WEEK
```

```r
source("C:/Users/YourName/Documents/NFL_betting_model/og_odds.R")
```

### During the Week (2 minutes, 2-3x)

**Check Line Movement:**
```r
source("C:/Users/YourName/Documents/NFL_betting_model/og_odds.R")
```

**Recommended times:**
- Tuesday morning (lines settle)
- Thursday evening (injury news)
- Saturday afternoon (sharp action)

### Sunday Morning (5 minutes)

**Final Check (2 hours before games):**
```r
source("C:/Users/YourName/Documents/NFL_betting_model/og_odds.R")
```

**Review:**
- ✅ Edges still exist?
- ✅ Any major line movements?
- ✅ Last-minute injury news?

### Monday (Next Week) - 10 minutes

**Track Results:**
- Log wins/losses
- Calculate ROI
- Record Closing Line Value (CLV)
- Update performance tracker

---

## 📊 Output Files

### Week_X_Model_Output.xlsx

**Sheet 1: Betting Summary**
- Game matchups
- Predicted margins
- Confidence tiers
- Betting recommendations

**Sheet 2: Detailed Analysis**
- All features and calculations
- Component ratings
- Situational adjustments

**Sheet 3: Offense Rankings**
- Team offense power rankings
- Rolling EPA, success rate, explosiveness

**Sheet 4: Defense Rankings**
- Team defense power rankings
- Defensive efficiency metrics

### betting_picks_weekX.xlsx (from og_odds.R)

**Summary Tab:**
- Total games analyzed
- Profitable bets found
- EV tier breakdown
- Average edge

**Profitable_Bets Tab:**
- Only bets with edges ≥1.5 points
- Sorted by edge size (largest first)
- Includes context notes (weather, rest, etc.)

**All_Games Tab:**
- Every game with model vs Vegas comparison
- Even games without edges (for reference)

### betting_edges.png

Visual chart showing:
- Top 12 games by edge size
- Green bars = value bets (≥1.5 pt edge)
- Gray bars = no value
- Red dashed lines = minimum edge threshold

---

## ⚙️ Configuration

### Pipeline Settings (pipeline_db_21_25.R)

```r
CURRENT_SEASON <- 2025      # Current NFL season
CURRENT_WEEK <- 11          # Last completed week (has data)
PREDICTION_WEEK <- 12       # Week you're predicting
START_SEASON <- 2021        # How far back to include data
BASE_DIR <- "C:/path"       # Your project directory
```

### Odds Integration Settings (og_odds.R)

```r
SEASON <- 2025              # Must match CURRENT_SEASON
WEEK <- 12                  # Must match PREDICTION_WEEK
MIN_EDGE_THRESHOLD <- 1.5   # Minimum edge to flag (points)
```

**Adjusting Edge Threshold:**
- **1.5 pts:** Standard (recommended)
- **1.0 pts:** More bets, lower quality
- **2.5 pts:** Fewer bets, higher quality
- **4.0 pts:** Only elite opportunities

### Team Abbreviations (nflfastR Standard)

```r
# Historical team relocations handled automatically:
'OAK' → 'LV'   # Oakland → Las Vegas Raiders
'SD'  → 'LAC'  # San Diego → Los Angeles Chargers
'STL' → 'LA'   # St. Louis → Los Angeles Rams

# Note: LA = Rams (not LAR), LAC = Chargers
```

---

## 🔑 API Requirements

### 1. The Odds API (Required)

**Purpose:** Fetch real-time betting lines

**Free Tier:**
- 500 requests/month
- 1 request = all NFL games with odds
- ~3 checks per day for entire season

**Sign Up:**
1. Visit [https://the-odds-api.com/](https://the-odds-api.com/)
2. Create account
3. Copy API key to `config/.env`

**Usage:** Automatically called by `og_odds.R`

### 2. SportsData.io (Optional but Recommended)

**Purpose:** Fetch injury reports

**Free Tier:**
- 1,000 requests/month
- Updates daily

**Sign Up:**
1. Visit [https://sportsdata.io/](https://sportsdata.io/)
2. Select NFL package
3. Copy API key to `config/.env`

**Usage:** Automatically called by `pipeline_db_21_25.R`

### 3. Weather API (Optional)

**Purpose:** Game-time weather forecasts

**Free Tier:**
- 1 million requests/month

**Sign Up:**
1. Visit [https://www.weatherapi.com/](https://www.weatherapi.com/)
2. Get API key
3. Copy to `config/.env`

**Usage:** Called by `weather_fetcher.R` (if enabled)

---

## 🧮 Model Methodology

### Data Sources

**Primary:** nflfastR (via nflreadr package)
- Play-by-play data (1999-present)
- Schedule and scores
- Advanced metrics pre-calculated

**Secondary:**
- The Odds API (betting lines)
- SportsData.io (injuries)
- Weather API (conditions)

### Feature Engineering

**Offensive Metrics:**
- EPA per play (overall, pass, rush)
- Success rate (% of "successful" plays)
- Explosive play rate (20+ yd pass, 10+ yd run)
- Yards per play
- Red zone efficiency
- Third down conversion rate
- Turnover rate

**Defensive Metrics:**
- All offensive metrics (from defensive perspective)
- Sacks generated
- Turnovers forced
- Opponent explosiveness allowed

**Rolling Windows:**
- **3-game:** Recent form (primary)
- **5-game:** Broader trend (secondary)
- **Trends:** Change over time (momentum)

**Situational Context:**
- Home field advantage (2.5 pts baseline)
- Rest days (0.5 pts per day edge)
- Travel distance (penalties for long trips)
- Weather impact (temp, wind, precipitation)
- Division rivalry (-1.0 pt typically closer)
- Injury impact (QB = -4 pts, key players scaled)

### Model Architecture

**Type:** Hybrid rating-based + regression

**Not included (intentionally):**
- Machine learning (RF, XGBoost) - overfits, less interpretable
- Complex ensembles - diminishing returns
- Player-level props - requires separate model

**Why this approach works:**
- ✅ Transparent (can explain every prediction)
- ✅ Stable (doesn't overfit to noise)
- ✅ Fast (runs in minutes, not hours)
- ✅ Interpretable (see which factors matter)

### Validation Strategy

**Time-series splits only** (no random CV):
- Never use future data to predict past
- Rolling window validation
- Track performance on out-of-sample data

**Metrics tracked:**
- MAE (mean absolute error) on point margin
- Win percentage accuracy
- ATS (against the spread) win rate
- CLV (closing line value) - key indicator

---

## 📈 Performance Tracking

### Key Metrics

**1. ROI (Return on Investment)**
```
ROI = (Total Winnings - Total Losses) / Total Amount Wagered × 100%

Example:
  10 bets × $100 = $1,000 wagered
  6 wins × $110 = $660 won
  4 losses × $100 = $400 lost
  Net = $660 - $400 = $260
  ROI = $260 / $1,000 = 26%
```

**2. CLV (Closing Line Value)**
```
CLV = Your Line - Closing Line

Example:
  You bet: BAL -2.5
  Closing line: BAL -4.0
  CLV = -2.5 - (-4.0) = +1.5 points

Positive CLV = Good (you beat the closing line)
```

**3. ATS (Against the Spread)**
```
ATS Win Rate = Spread Bets Won / Total Spread Bets

Target: >52.4% (breakeven with -110 juice)
Good: >55%
Excellent: >58%
```

**4. Edge Accuracy**
```
How often do edges ≥X points hit?

Track separately:
- Elite edges (≥4 pts): Should hit 60%+
- Strong edges (≥2.5 pts): Should hit 56%+
- Good edges (≥1.5 pts): Should hit 53%+
```

### Sample Tracking Spreadsheet

| Week | Game | Pick | Edge | Closing Line | Result | Margin | W/L | CLV | ROI |
|------|------|------|------|--------------|--------|--------|-----|-----|-----|
| 11 | BAL@CLE | BAL-7.5 | 9.7 | -8.5 | W | -14 | +110 | +1.0 | +10% |
| 11 | NYJ@NE | NE-12.5 | 8.9 | -13.5 | L | -8 | -100 | +1.0 | -10% |
| 11 | SF@ARI | SF-3.0 | 7.2 | -4.0 | W | -10 | +110 | +1.0 | +10% |

**Weekly Summary:**
- Total Bets: 3
- Wins: 2 (67%)
- Net: +$120
- ROI: +40%
- Avg CLV: +1.0 pts ✅

---

## 🔧 Troubleshooting

### Pipeline Errors

**Error: "No offensive stats found"**

**Solution:**
```r
# Check if teams have data for CURRENT_WEEK
latest_offense <- offense_rolling %>%
  filter(season == CURRENT_SEASON) %>%
  group_by(offense_team) %>%
  filter(week == max(week))

View(latest_offense)

# If empty, reduce CURRENT_WEEK by 1
```

**Error: "Database connection failed"**

**Solution:**
```r
# Delete and rebuild database
file.remove("pbp_db_2021_2025.sqlite")
source("pipeline_db_21_25.R")  # Will rebuild
```

**Error: "All predicted margins are NA"**

**Solution:**
```r
# Check if rolling features calculated
View(latest_offense)  # Should have roll3_epa values

# If all NA:
# 1. Verify CURRENT_WEEK has completed games
# 2. Check teams played at least 3 games this season
```

### Odds Integration Errors

**Error: "0 games matched"**

**Cause:** Team abbreviation mismatch (LA vs LAR)

**Solution:**
```r
# Check your model predictions
View(model_predictions)  # Should show "LA" for Rams

# Check odds data
View(odds_processed)  # Should also show "LA" for Rams

# If mismatch: Update team_name_to_abbr in og_odds.R line 341
```

**Error: "API Error: Status 401"**

**Solution:**
```r
# Check API key validity
Sys.getenv("ODDS_API_KEY")  # Should show your key

# Verify at: https://the-odds-api.com/account/
# Check quota remaining
```

**Error: "No spread data available"**

**Solution:**
- Games are 6+ days away (odds not posted)
- Season ended (no upcoming games)
- API quota exceeded (check account)

### Data Quality Issues

**Issue: Predictions seem wrong**

**Debugging steps:**
```r
# 1. Check sample team ratings
latest_offense %>% 
  filter(offense_team == "KC") %>% 
  select(offense_team, week, roll3_epa, roll3_success)

# 2. Check specific game prediction
predictions %>% 
  filter(away_team == "KC" | home_team == "KC") %>%
  select(away_team, home_team, predicted_margin, 
         away_offense_rating, home_offense_rating)

# 3. Verify adjustments are reasonable
predictions %>%
  select(away_team, home_team, predicted_margin,
         home_field_adj, rest_adj, travel_adj, weather_adj)
```

**Issue: All edges are negative**

**This is normal!** It means:
- Vegas is more bullish on favorites
- Your model is more conservative
- Bet the underdogs in these cases

**Issue: No profitable bets for weeks**

**This is also normal!**
- Vegas is sharp - edges are rare
- Lower threshold to 1.0 if needed
- Quality over quantity

---

## 🤝 Contributing

Contributions welcome! Areas for improvement:

### High Priority
- [ ] Player prop projections
- [ ] ML model comparison (XGBoost baseline)
- [ ] Automated bet tracking
- [ ] Web dashboard for results

### Medium Priority
- [ ] Historical backtesting framework
- [ ] Advanced weather integration
- [ ] Opponent adjustments (strength of schedule)
- [ ] Live in-game predictions

### Low Priority
- [ ] Python port of pipeline
- [ ] Docker containerization
- [ ] Cloud deployment (AWS/GCP)

**How to contribute:**
1. Fork the repo
2. Create feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Open Pull Request

---

## ⚠️ Disclaimer

**FOR EDUCATIONAL AND RESEARCH PURPOSES ONLY**

This model is provided for:
- ✅ Learning sports analytics
- ✅ Understanding betting markets
- ✅ Research and data science practice

This model is NOT:
- ❌ Financial advice
- ❌ Guaranteed to win money
- ❌ A get-rich-quick scheme

**Important Warnings:**

1. **Past performance ≠ future results**
   - Model accuracy can vary significantly
   - No betting system is foolproof

2. **Gambling is risky**
   - Only bet what you can afford to lose
   - Set strict bankroll limits
   - Seek help if gambling becomes a problem

3. **Legal compliance**
   - Sports betting is illegal in some jurisdictions
   - Check your local laws before placing bets
   - Some sportsbooks may ban winning players

4. **Responsible gambling resources:**
   - National Council on Problem Gambling: 1-800-522-4700
   - [https://www.ncpgambling.org/](https://www.ncpgambling.org/)

**The author(s) assume NO liability for:**
- Financial losses from using this model
- Legal issues related to sports betting
- Addiction or gambling problems

**USE AT YOUR OWN RISK**

---

## 📄 License

MIT License

Copyright (c) 2024 [Your Name]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

## 🙏 Acknowledgments

**Data & Tools:**
- [nflfastR](https://www.nflfastr.com/) - Ben Baldwin, Sebastian Carl, and the nflverse team
- [The Odds API](https://the-odds-api.com/) - Real-time odds data
- [SportsData.io](https://sportsdata.io/) - Injury data
- [RStudio](https://posit.co/) - Development environment

**Inspiration:**
- [NFLfastR Beginner's Guide](https://www.nflfastr.com/articles/beginners_guide.html)
- [Expected Points methodology](https://www.opensourcefootball.com/posts/2020-09-28-nflfastr-ep-wp-and-cp-models/)
- [The Mockup Blog - NFL Database](https://themockup.blog/posts/2019-04-28-nflfastr-dbplyr-rsqlite/)

**Community:**
- r/NFLstats subreddit
- Sports analytics Twitter (#nflverse)
- Open Source Football

---

## 📞 Contact & Support

**Issues:** [GitHub Issues](https://github.com/hatpat10/NFL_betting_model/issues)

**Discussions:** [GitHub Discussions](https://github.com/hatpat10/NFL_betting_model/discussions)

**Email:** [Your email if you want to include it]

---

## 🗺️ Roadmap

### Version 2.0 (Next Season - 2025)
- [ ] Machine learning baseline comparison
- [ ] Automated backtesting framework
- [ ] Player prop projections
- [ ] Web dashboard

### Version 2.1
- [ ] Live in-game predictions
- [ ] Advanced weather modeling
- [ ] Strength of schedule adjustments

### Version 3.0
- [ ] Multi-sport expansion (NBA, MLB, NHL)
- [ ] Cloud deployment
- [ ] API for programmatic access

---

## 📚 Additional Resources

**Learn More:**
- [WEEKLY_WORKFLOW_CHECKLIST.md](WEEKLY_WORKFLOW_CHECKLIST.md) - Step-by-step weekly guide
- [NFL_MODEL_WORKFLOW_GUIDE.md](NFL_MODEL_WORKFLOW_GUIDE.md) - Detailed methodology

**External Links:**
- [nflfastR documentation](https://www.nflfastr.com/)
- [Expected Points primer](https://www.opensourcefootball.com/posts/2020-09-28-nflfastr-ep-wp-and-cp-models/)
- [Sports betting 101](https://www.actionnetwork.com/education/sports-betting-101)

---

**⭐ If this helped you, please star the repo!**

**🏈💰 Good luck with your predictions!**

---

*Last Updated: November 13, 2024*  
*Version: 1.0.0*
