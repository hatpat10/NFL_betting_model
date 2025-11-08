# ============================================================================
# FETCH 2025 NFL SEASON HISTORICAL ODDS (WEEK 5 ONWARDS)
# ============================================================================
# This script fetches all historical betting lines for the 2025 NFL season
# starting from Week 5 through the current week
# ============================================================================

library(tidyverse)
library(httr)
library(jsonlite)
library(DBI)
library(RSQLite)
library(nflreadr)

# ============================================================================
# CONFIGURATION FOR 2025 SEASON
# ============================================================================

SPORTSDATA_API_KEY <- Sys.getenv("SPORTSDATA_API_KEY")
if (SPORTSDATA_API_KEY == "") {
  # Try loading from .env file if not in environment
  if (file.exists("config/.env")) {
    readRenviron("config/.env")
    SPORTSDATA_API_KEY <- Sys.getenv("SPORTSDATA_API_KEY")
  }
  if (SPORTSDATA_API_KEY == "") {
    stop("Please set SPORTSDATA_API_KEY in your .Renviron or config/.env file")
  }
}

BASE_URL <- "https://api.sportsdata.io/v3/nfl/odds/json"
DB_PATH <- "db/nfl_odds_2025.sqlite"

# 2025 Season Configuration
SEASON <- 2025
START_WEEK <- 5  # Start from Week 5
CURRENT_WEEK <- 10  # Update this to current week

cat("\n", strrep("=", 70), "\n", sep = "")
cat("NFL 2025 SEASON - HISTORICAL ODDS FETCHER\n")
cat("Fetching Weeks", START_WEEK, "through", CURRENT_WEEK, "\n")
cat(strrep("=", 70), "\n\n")

# ============================================================================
# DATABASE SETUP
# ============================================================================

setup_database <- function() {
  dir.create("db", showWarnings = FALSE)
  con <- dbConnect(SQLite(), DB_PATH)
  
  # Create comprehensive odds table
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS historical_odds_2025 (
      game_key TEXT,
      season INTEGER,
      season_type INTEGER,
      week INTEGER,
      game_date TEXT,
      home_team TEXT,
      away_team TEXT,
      home_team_abbr TEXT,
      away_team_abbr TEXT,
      home_score INTEGER,
      away_score INTEGER,
      sportsbook TEXT,
      sportsbook_id INTEGER,
      
      -- Spread data
      home_spread REAL,
      away_spread REAL,
      home_spread_payout INTEGER,
      away_spread_payout INTEGER,
      
      -- Moneyline data
      home_moneyline INTEGER,
      away_moneyline INTEGER,
      
      -- Total data
      over_under REAL,
      over_payout INTEGER,
      under_payout INTEGER,
      
      -- Timestamps
      odds_created TEXT,
      odds_updated TEXT,
      fetched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      
      PRIMARY KEY (game_key, sportsbook, odds_updated)
    )
  ")
  
  # Create indices for faster queries
  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_week ON historical_odds_2025(season, week)")
  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_teams ON historical_odds_2025(home_team_abbr, away_team_abbr)")
  dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_game ON historical_odds_2025(game_key)")
  
  dbDisconnect(con)
  cat("✓ Database initialized:", DB_PATH, "\n\n")
}

# ============================================================================
# TEAM ABBREVIATION MAPPING
# ============================================================================

TEAM_MAP <- c(
  "Arizona Cardinals" = "ARI", "ARI" = "ARI",
  "Atlanta Falcons" = "ATL", "ATL" = "ATL",
  "Baltimore Ravens" = "BAL", "BAL" = "BAL",
  "Buffalo Bills" = "BUF", "BUF" = "BUF",
  "Carolina Panthers" = "CAR", "CAR" = "CAR",
  "Chicago Bears" = "CHI", "CHI" = "CHI",
  "Cincinnati Bengals" = "CIN", "CIN" = "CIN",
  "Cleveland Browns" = "CLE", "CLE" = "CLE",
  "Dallas Cowboys" = "DAL", "DAL" = "DAL",
  "Denver Broncos" = "DEN", "DEN" = "DEN",
  "Detroit Lions" = "DET", "DET" = "DET",
  "Green Bay Packers" = "GB", "GB" = "GB",
  "Houston Texans" = "HOU", "HOU" = "HOU",
  "Indianapolis Colts" = "IND", "IND" = "IND",
  "Jacksonville Jaguars" = "JAX", "JAX" = "JAX", "JAC" = "JAX",
  "Kansas City Chiefs" = "KC", "KC" = "KC",
  "Las Vegas Raiders" = "LV", "LV" = "LV",
  "Los Angeles Chargers" = "LAC", "LAC" = "LAC",
  "Los Angeles Rams" = "LAR", "LAR" = "LAR", "LA" = "LAR",
  "Miami Dolphins" = "MIA", "MIA" = "MIA",
  "Minnesota Vikings" = "MIN", "MIN" = "MIN",
  "New England Patriots" = "NE", "NE" = "NE",
  "New Orleans Saints" = "NO", "NO" = "NO",
  "New York Giants" = "NYG", "NYG" = "NYG",
  "New York Jets" = "NYJ", "NYJ" = "NYJ",
  "Philadelphia Eagles" = "PHI", "PHI" = "PHI",
  "Pittsburgh Steelers" = "PIT", "PIT" = "PIT",
  "San Francisco 49ers" = "SF", "SF" = "SF",
  "Seattle Seahawks" = "SEA", "SEA" = "SEA",
  "Tampa Bay Buccaneers" = "TB", "TB" = "TB",
  "Tennessee Titans" = "TEN", "TEN" = "TEN",
  "Washington Commanders" = "WAS", "WAS" = "WAS",
  "Washington" = "WAS"
)

# ============================================================================
# FETCH ODDS FOR A SINGLE WEEK
# ============================================================================

fetch_week_odds <- function(season, week, season_type = "REG") {
  
  # Map season type (REG=1, PRE=2, POST=3)
  season_code <- ifelse(season_type == "REG", 1, ifelse(season_type == "PRE", 2, 3))
  
  # Build endpoint
  endpoint <- paste0(BASE_URL, "/GameOddsByWeek/", season, season_code, "/", week)
  
  cat("  Fetching Week", week, "... ")
  
  # Make API request
  response <- GET(
    url = endpoint,
    add_headers(`Ocp-Apim-Subscription-Key` = SPORTSDATA_API_KEY),
    timeout(30)
  )
  
  # Check response
  if (status_code(response) != 200) {
    cat("✗ Error:", status_code(response), "\n")
    return(NULL)
  }
  
  # Parse JSON
  odds_data <- content(response, "text", encoding = "UTF-8") %>%
    fromJSON(flatten = TRUE)
  
  if (is.null(odds_data) || nrow(odds_data) == 0) {
    cat("✗ No data\n")
    return(NULL)
  }
  
  cat("✓", nrow(odds_data), "games\n")
  
  # Process each game
  all_odds <- list()
  
  for (i in 1:nrow(odds_data)) {
    game <- odds_data[i, ]
    
    # Skip if no pregame odds
    if (is.null(game$PregameOdds) || length(game$PregameOdds[[1]]) == 0) {
      next
    }
    
    pregame_odds <- game$PregameOdds[[1]]
    
    # Process each sportsbook
    for (j in 1:nrow(pregame_odds)) {
      book <- pregame_odds[j, ]
      
      odds_record <- tibble(
        game_key = game$GameKey,
        season = game$Season,
        season_type = game$SeasonType,
        week = game$Week,
        game_date = game$Date,
        home_team = game$HomeTeamName,
        away_team = game$AwayTeamName,
        home_team_abbr = ifelse(game$HomeTeamName %in% names(TEAM_MAP),
                                TEAM_MAP[game$HomeTeamName], game$HomeTeamName),
        away_team_abbr = ifelse(game$AwayTeamName %in% names(TEAM_MAP),
                                TEAM_MAP[game$AwayTeamName], game$AwayTeamName),
        home_score = game$HomeScore,
        away_score = game$AwayScore,
        sportsbook = book$Sportsbook,
        sportsbook_id = book$SportsbookId,
        home_spread = book$HomePointSpread,
        away_spread = book$AwayPointSpread,
        home_spread_payout = book$HomePointSpreadPayout,
        away_spread_payout = book$AwayPointSpreadPayout,
        home_moneyline = book$HomeMoneyLine,
        away_moneyline = book$AwayMoneyLine,
        over_under = book$OverUnder,
        over_payout = book$OverPayout,
        under_payout = book$UnderPayout,
        odds_created = book$Created,
        odds_updated = book$Updated
      )
      
      all_odds[[length(all_odds) + 1]] <- odds_record
    }
  }
  
  if (length(all_odds) == 0) {
    return(NULL)
  }
  
  return(bind_rows(all_odds))
}

# ============================================================================
# FETCH ALL WEEKS FOR 2025 SEASON
# ============================================================================

fetch_2025_season_odds <- function() {
  
  cat("Fetching 2025 NFL Season Odds\n")
  cat(strrep("-", 40), "\n")
  
  all_weeks_data <- list()
  total_games <- 0
  total_records <- 0
  
  for (week in START_WEEK:CURRENT_WEEK) {
    
    # Fetch odds for this week
    week_odds <- fetch_week_odds(SEASON, week, "REG")
    
    if (!is.null(week_odds) && nrow(week_odds) > 0) {
      all_weeks_data[[length(all_weeks_data) + 1]] <- week_odds
      
      # Count unique games
      n_games <- length(unique(week_odds$game_key))
      total_games <- total_games + n_games
      total_records <- total_records + nrow(week_odds)
    }
    
    # Small delay to be respectful to API
    Sys.sleep(0.5)
  }
  
  cat(strrep("-", 40), "\n")
  
  if (length(all_weeks_data) == 0) {
    cat("✗ No odds data retrieved\n")
    return(NULL)
  }
  
  # Combine all weeks
  combined_odds <- bind_rows(all_weeks_data)
  
  cat("\n✓ FETCH COMPLETE:\n")
  cat("  Total Weeks:", length(all_weeks_data), "\n")
  cat("  Total Games:", total_games, "\n")
  cat("  Total Records:", total_records, "\n")
  cat("  Sportsbooks:", paste(unique(combined_odds$sportsbook)[1:5], collapse = ", "), "...\n")
  
  return(combined_odds)
}

# ============================================================================
# STORE ODDS IN DATABASE
# ============================================================================

store_odds <- function(odds_df) {
  
  if (is.null(odds_df) || nrow(odds_df) == 0) {
    cat("No data to store\n")
    return()
  }
  
  con <- dbConnect(SQLite(), DB_PATH)
  
  # Add fetched_at timestamp
  odds_df$fetched_at <- Sys.time()
  
  # Store in database (replace existing data for these weeks)
  dbWriteTable(con, "historical_odds_2025", odds_df, 
               append = TRUE, row.names = FALSE)
  
  # Get summary statistics
  total_records <- dbGetQuery(con, "SELECT COUNT(*) as n FROM historical_odds_2025")$n
  total_games <- dbGetQuery(con, "SELECT COUNT(DISTINCT game_key) as n FROM historical_odds_2025")$n
  total_books <- dbGetQuery(con, "SELECT COUNT(DISTINCT sportsbook) as n FROM historical_odds_2025")$n
  weeks_covered <- dbGetQuery(con, "SELECT MIN(week) as min_week, MAX(week) as max_week FROM historical_odds_2025")
  
  dbDisconnect(con)
  
  cat("\n✓ DATABASE UPDATE COMPLETE:\n")
  cat("  Total Records:", total_records, "\n")
  cat("  Total Games:", total_games, "\n")
  cat("  Total Sportsbooks:", total_books, "\n")
  cat("  Weeks Covered:", weeks_covered$min_week, "-", weeks_covered$max_week, "\n")
}

# ============================================================================
# GET CONSENSUS LINES FOR A SPECIFIC WEEK
# ============================================================================

get_week_consensus <- function(week) {
  
  con <- dbConnect(SQLite(), DB_PATH)
  
  query <- "
    SELECT 
      game_key,
      week,
      game_date,
      home_team_abbr,
      away_team_abbr,
      home_score,
      away_score,
      
      -- Consensus lines (average across books)
      ROUND(AVG(home_spread), 1) as consensus_spread,
      ROUND(AVG(over_under), 1) as consensus_total,
      ROUND(AVG(home_moneyline), 0) as consensus_home_ml,
      ROUND(AVG(away_moneyline), 0) as consensus_away_ml,
      
      -- Line ranges
      MIN(home_spread) as min_spread,
      MAX(home_spread) as max_spread,
      MIN(over_under) as min_total,
      MAX(over_under) as max_total,
      
      -- Number of books
      COUNT(DISTINCT sportsbook) as n_books,
      GROUP_CONCAT(DISTINCT sportsbook) as books_list
      
    FROM historical_odds_2025
    WHERE season = ? AND week = ?
    GROUP BY game_key, home_team_abbr, away_team_abbr
    ORDER BY game_date, game_key
  "
  
  consensus <- dbGetQuery(con, query, params = list(SEASON, week))
  dbDisconnect(con)
  
  if (nrow(consensus) == 0) {
    cat("No consensus data for Week", week, "\n")
    return(NULL)
  }
  
  # Add matchup key
  consensus$matchup_key <- paste(consensus$away_team_abbr, "at", consensus$home_team_abbr)
  
  return(consensus)
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

cat("Step 1: Initialize Database\n")
setup_database()

cat("\nStep 2: Fetch 2025 Season Odds (Weeks", START_WEEK, "-", CURRENT_WEEK, ")\n")
all_odds <- fetch_2025_season_odds()

if (!is.null(all_odds)) {
  cat("\nStep 3: Store in Database\n")
  store_odds(all_odds)
  
  cat("\nStep 4: Generate Week-by-Week Summary\n")
  cat(strrep("-", 60), "\n")
  
  for (week in START_WEEK:CURRENT_WEEK) {
    consensus <- get_week_consensus(week)
    if (!is.null(consensus)) {
      cat(sprintf("Week %2d: %2d games, %d books\n", 
                  week, nrow(consensus), max(consensus$n_books)))
      
      # Save consensus to CSV
      output_file <- sprintf("reports/consensus_odds_2025_week_%02d.csv", week)
      dir.create("reports", showWarnings = FALSE)
      write_csv(consensus, output_file)
    }
  }
}

cat("\n", strrep("=", 70), "\n", sep = "")
cat("✓ 2025 SEASON HISTORICAL ODDS FETCH COMPLETE\n")
cat("  Database:", DB_PATH, "\n")
cat("  Consensus files saved to: reports/consensus_odds_2025_week_*.csv\n")
cat(strrep("=", 70), "\n\n")

# ============================================================================
# QUICK ACCESS FUNCTIONS
# ============================================================================

# Function to get odds for model evaluation
get_odds_for_evaluation <- function(week) {
  consensus <- get_week_consensus(week)
  if (is.null(consensus)) {
    return(NULL)
  }
  
  # Format for model integration
  odds_for_model <- consensus %>%
    select(
      matchup_key,
      home_team = home_team_abbr,
      away_team = away_team_abbr,
      vegas_spread = consensus_spread,
      vegas_total = consensus_total,
      home_ml = consensus_home_ml,
      away_ml = consensus_away_ml,
      actual_home_score = home_score,
      actual_away_score = away_score
    ) %>%
    mutate(
      actual_margin = actual_home_score - actual_away_score,
      actual_total = actual_home_score + actual_away_score,
      home_cover = actual_margin + vegas_spread > 0,
      over = actual_total > vegas_total
    )
  
  return(odds_for_model)
}

# Example: Get Week 10 odds for evaluation
# week_10_odds <- get_odds_for_evaluation(10)