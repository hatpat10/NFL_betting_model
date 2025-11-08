# ============================================================================
# BUILD HISTORICAL ODDS DATABASE
# ============================================================================
# Run this script regularly (daily/multiple times per week) to build your own
# historical odds database since The Odds API doesn't provide past odds
# ============================================================================

library(tidyverse)
library(httr)
library(jsonlite)
library(DBI)
library(RSQLite)

# Configuration
ODDS_API_KEY <- "a35f7d5b7f91dbca7a9364b72c1b1cf2"
DB_PATH <- "db/historical_odds.sqlite"

# ============================================================================
# FETCH CURRENT ODDS (FOR FUTURE GAMES)
# ============================================================================

fetch_current_nfl_odds <- function(api_key) {
  base_url <- "https://api.the-odds-api.com/v4/sports/americanfootball_nfl/odds/"
  
  params <- list(
    apiKey = api_key,
    regions = "us",
    markets = "spreads,totals,h2h",
    oddsFormat = "american",
    dateFormat = "iso"
  )
  
  response <- httr::GET(url = base_url, query = params)
  
  if (httr::status_code(response) != 200) {
    stop("API Error: ", httr::status_code(response))
  }
  
  odds_data <- httr::content(response, "text", encoding = "UTF-8") %>%
    jsonlite::fromJSON(flatten = TRUE)
  
  return(odds_data)
}

# ============================================================================
# PROCESS AND STORE ODDS
# ============================================================================

process_and_store_odds <- function() {
  
  # Fetch current odds
  cat("Fetching current NFL odds...\n")
  odds_raw <- fetch_current_nfl_odds(ODDS_API_KEY)
  
  if (is.null(odds_raw) || nrow(odds_raw) == 0) {
    cat("No odds available at this time\n")
    return(NULL)
  }
  
  # Process each game
  all_odds <- list()
  
  for (i in 1:nrow(odds_raw)) {
    game <- odds_raw[i, ]
    
    # Skip if no bookmakers
    if (is.null(game$bookmakers) || length(game$bookmakers[[1]]) == 0) next
    
    bookmakers <- game$bookmakers[[1]]
    
    for (j in 1:nrow(bookmakers)) {
      book <- bookmakers[j, ]
      markets <- book$markets[[1]]
      
      if (!is.data.frame(markets)) next
      
      # Extract spreads
      spread_market <- markets[markets$key == "spreads", ]
      if (nrow(spread_market) > 0) {
        outcomes <- spread_market$outcomes[[1]]
        
        for (k in 1:nrow(outcomes)) {
          all_odds[[length(all_odds) + 1]] <- data.frame(
            snapshot_time = Sys.time(),
            game_id = game$id,
            commence_time = game$commence_time,
            home_team = game$home_team,
            away_team = game$away_team,
            bookmaker = book$key,
            bookmaker_title = book$title,
            market = "spread",
            team = outcomes$name[k],
            line = outcomes$point[k],
            odds = outcomes$price[k],
            stringsAsFactors = FALSE
          )
        }
      }
      
      # Extract totals
      totals_market <- markets[markets$key == "totals", ]
      if (nrow(totals_market) > 0) {
        outcomes <- totals_market$outcomes[[1]]
        
        for (k in 1:nrow(outcomes)) {
          all_odds[[length(all_odds) + 1]] <- data.frame(
            snapshot_time = Sys.time(),
            game_id = game$id,
            commence_time = game$commence_time,
            home_team = game$home_team,
            away_team = game$away_team,
            bookmaker = book$key,
            bookmaker_title = book$title,
            market = "total",
            team = outcomes$name[k],  # "Over" or "Under"
            line = outcomes$point[k],
            odds = outcomes$price[k],
            stringsAsFactors = FALSE
          )
        }
      }
      
      # Extract moneylines
      ml_market <- markets[markets$key == "h2h", ]
      if (nrow(ml_market) > 0) {
        outcomes <- ml_market$outcomes[[1]]
        
        for (k in 1:nrow(outcomes)) {
          all_odds[[length(all_odds) + 1]] <- data.frame(
            snapshot_time = Sys.time(),
            game_id = game$id,
            commence_time = game$commence_time,
            home_team = game$home_team,
            away_team = game$away_team,
            bookmaker = book$key,
            bookmaker_title = book$title,
            market = "moneyline",
            team = outcomes$name[k],
            line = NA,  # No line for ML
            odds = outcomes$price[k],
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }
  
  # Convert to dataframe
  odds_df <- bind_rows(all_odds)
  
  cat("Processed", nrow(odds_df), "odds records from", 
      length(unique(odds_df$game_id)), "games\n")
  
  # Store in database
  store_in_database(odds_df)
  
  return(odds_df)
}

# ============================================================================
# DATABASE STORAGE
# ============================================================================

store_in_database <- function(odds_df) {
  
  # Create/connect to database
  con <- dbConnect(SQLite(), DB_PATH)
  
  # Create table if it doesn't exist
  if (!dbExistsTable(con, "odds_snapshots")) {
    dbExecute(con, "
      CREATE TABLE odds_snapshots (
        snapshot_time TIMESTAMP,
        game_id TEXT,
        commence_time TEXT,
        home_team TEXT,
        away_team TEXT,
        bookmaker TEXT,
        bookmaker_title TEXT,
        market TEXT,
        team TEXT,
        line REAL,
        odds REAL,
        PRIMARY KEY (snapshot_time, game_id, bookmaker, market, team)
      )
    ")
    
    cat("Created new odds_snapshots table\n")
  }
  
  # Insert new records
  dbWriteTable(con, "odds_snapshots", odds_df, append = TRUE, row.names = FALSE)
  
  # Get summary
  total_records <- dbGetQuery(con, "SELECT COUNT(*) as n FROM odds_snapshots")$n
  unique_games <- dbGetQuery(con, "SELECT COUNT(DISTINCT game_id) as n FROM odds_snapshots")$n
  
  cat("Database now contains:\n")
  cat("  - Total records:", total_records, "\n")
  cat("  - Unique games:", unique_games, "\n")
  
  dbDisconnect(con)
}

# ============================================================================
# RETRIEVE HISTORICAL ODDS FOR ANALYSIS
# ============================================================================

get_historical_odds <- function(season, week) {
  
  con <- dbConnect(SQLite(), DB_PATH)
  
  # Load NFL schedule to get game dates
  schedule <- nflreadr::load_schedules(season) %>%
    filter(week == !!week)
  
  # Get date range for the week
  week_start <- min(as.Date(schedule$gameday)) - 7
  week_end <- max(as.Date(schedule$gameday)) + 1
  
  # Query historical odds
  query <- sprintf("
    SELECT * FROM odds_snapshots 
    WHERE DATE(commence_time) BETWEEN '%s' AND '%s'
    ORDER BY snapshot_time, game_id, bookmaker
  ", week_start, week_end)
  
  odds_historical <- dbGetQuery(con, query)
  dbDisconnect(con)
  
  if (nrow(odds_historical) == 0) {
    cat("No historical odds found for Season", season, "Week", week, "\n")
    cat("Date range searched:", week_start, "to", week_end, "\n")
    return(NULL)
  }
  
  # Process to get opening and closing lines
  odds_summary <- odds_historical %>%
    group_by(game_id, home_team, away_team, bookmaker, market, team) %>%
    summarize(
      first_snapshot = min(snapshot_time),
      last_snapshot = max(snapshot_time),
      opening_line = first(line),
      closing_line = last(line),
      opening_odds = first(odds),
      closing_odds = last(odds),
      line_movement = closing_line - opening_line,
      n_snapshots = n(),
      .groups = 'drop'
    )
  
  return(odds_summary)
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Run the snapshot
cat("\n", strrep("=", 60), "\n", sep = "")
cat("NFL ODDS SNAPSHOT - ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat(strrep("=", 60), "\n\n")

process_and_store_odds()

cat("\n", strrep("=", 60), "\n", sep = "")
cat("✓ Snapshot complete\n")
cat("Schedule this script to run:\n")
cat("  - Monday morning (opening lines)\n")
cat("  - Wednesday evening (mid-week)\n")
cat("  - Friday evening (late week)\n")
cat("  - Sunday morning (closing lines)\n")
cat(strrep("=", 60), "\n")

# Example: Retrieve historical odds for analysis
# historical <- get_historical_odds(2025, 6)