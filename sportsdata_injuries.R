# ============================================================================
# SPORTSDATA.IO INJURY DATA FETCHER
# ============================================================================
# Fetches real-time NFL injury data from SportsData.io API
# API Endpoint: https://api.sportsdata.io/v3/nfl/projections/json/InjuredPlayers

# Load required packages
if (!require("httr")) install.packages("httr")
if (!require("jsonlite")) install.packages("jsonlite")
if (!require("dplyr")) install.packages("dplyr")

library(httr)
library(jsonlite)
library(dplyr)

# ============================================================================
# CONFIGURATION
# ============================================================================

# Your SportsData.io API key
SPORTSDATA_API_KEY <- "795cb44abbcd438f8d5d276caaad4632"

# API endpoints
SPORTSDATA_BASE_URL <- "https://api.sportsdata.io/v3/nfl/projections/json"
INJURIES_ENDPOINT <- "InjuredPlayers"

# Position value weights (for impact calculation)
POSITION_VALUES <- list(
  "QB" = 5.0,   # Quarterback - highest impact
  "LT" = 2.5,   # Left Tackle
  "WR1" = 2.0,  # Top receiver
  "EDGE" = 2.0, # Pass rusher
  "CB1" = 1.5,  # Top corner
  "RB" = 1.5,   # Running back
  "TE" = 1.0,   # Tight end
  "WR" = 1.0,   # Other receivers
  "OL" = 1.0,   # Other offensive line
  "DL" = 0.75,  # Defensive line
  "LB" = 0.75,  # Linebacker
  "CB" = 0.75,  # Other corners
  "S" = 0.5,    # Safety
  "K" = 0.25,   # Kicker
  "P" = 0.1     # Punter
)

# Injury status severity (impact multiplier)
STATUS_SEVERITY <- list(
  "Out" = 1.0,
  "Doubtful" = 0.75,
  "Questionable" = 0.3,
  "Probable" = 0.1,
  "IR" = 1.0,
  "PUP" = 1.0,
  "Suspension" = 1.0
)

# ============================================================================
# FUNCTION: Fetch Injured Players
# ============================================================================

fetch_injured_players <- function(api_key = SPORTSDATA_API_KEY) {
  
  cat("Fetching injury data from SportsData.io...\n")
  
  # Build URL
  url <- paste0(SPORTSDATA_BASE_URL, "/", INJURIES_ENDPOINT)
  
  # Make API request
  response <- tryCatch({
    GET(
      url,
      query = list(key = api_key),
      timeout(30)
    )
  }, error = function(e) {
    cat("Error connecting to SportsData.io API:", e$message, "\n")
    return(NULL)
  })
  
  # Check response
  if (is.null(response)) {
    cat("Failed to connect to API\n")
    return(NULL)
  }
  
  if (status_code(response) != 200) {
    cat("API returned error code:", status_code(response), "\n")
    cat("Response:", content(response, "text"), "\n")
    return(NULL)
  }
  
  # Parse JSON
  injury_data <- tryCatch({
    content(response, "text") %>%
      fromJSON(flatten = TRUE)
  }, error = function(e) {
    cat("Error parsing JSON response:", e$message, "\n")
    return(NULL)
  })
  
  if (is.null(injury_data) || nrow(injury_data) == 0) {
    cat("No injury data returned\n")
    return(NULL)
  }
  
  cat("✓ Retrieved", nrow(injury_data), "injury reports\n")
  
  return(injury_data)
}

# ============================================================================
# FUNCTION: Process and Clean Injury Data
# ============================================================================

process_injury_data <- function(raw_data, season = 2025, week = NULL) {
  
  if (is.null(raw_data) || nrow(raw_data) == 0) {
    cat("No data to process\n")
    return(list(
      detailed = data.frame(),
      summary = data.frame()
    ))
  }
  
  cat("Processing injury data...\n")
  
  # Clean and standardize the data
  injuries_clean <- raw_data %>%
    mutate(
      # Standardize team abbreviations (SportsData uses different codes)
      team = case_when(
        Team == "JAC" ~ "JAX",
        TRUE ~ Team
      ),
      
      # Clean position
      position = toupper(Position),
      
      # Standardize injury status
      status = case_when(
        Status == "Out" ~ "Out",
        Status == "Doubtful" ~ "Doubtful", 
        Status == "Questionable" ~ "Questionable",
        Status %in% c("Probable", "Questionable") ~ "Questionable",
        grepl("IR|Reserve", Status, ignore.case = TRUE) ~ "IR",
        grepl("PUP", Status, ignore.case = TRUE) ~ "PUP",
        grepl("Suspension|Suspended", Status, ignore.case = TRUE) ~ "Suspension",
        TRUE ~ Status
      ),
      
      # Player info
      player_name = paste(FirstName, LastName),
      
      # Get position group for value assessment
      position_group = case_when(
        position == "QB" ~ "QB",
        position %in% c("LT", "RT") ~ "OT",
        position %in% c("LG", "RG", "C") ~ "OG",
        position %in% c("WR", "WR1", "WR2") ~ "WR",
        position %in% c("RB", "FB") ~ "RB",
        position == "TE" ~ "TE",
        position %in% c("DE", "DT", "NT") ~ "DL",
        position %in% c("OLB", "MLB", "ILB", "LB") ~ "LB",
        position %in% c("CB", "CB1", "CB2") ~ "CB",
        position %in% c("SS", "FS", "S") ~ "S",
        position == "K" ~ "K",
        position == "P" ~ "P",
        TRUE ~ "OTHER"
      ),
      
      # Assign impact value
      impact_value = case_when(
        position == "QB" ~ 5.0,
        position %in% c("LT", "RT") ~ 2.5,
        position == "WR" & Number <= 2 ~ 2.0,  # Top 2 WRs
        position_group == "DL" & DeclaredInactive == FALSE ~ 2.0,  # Pass rushers
        position_group == "CB" & Number == 1 ~ 1.5,
        position_group == "RB" ~ 1.5,
        position_group == "TE" ~ 1.0,
        position_group == "WR" ~ 1.0,
        position_group == "OG" ~ 1.0,
        position_group %in% c("DL", "LB") ~ 0.75,
        position_group %in% c("CB", "S") ~ 0.75,
        position_group == "K" ~ 0.25,
        position_group == "P" ~ 0.1,
        TRUE ~ 0.5
      ),
      
      # Apply status severity multiplier
      severity_multiplier = case_when(
        status %in% c("Out", "IR", "PUP", "Suspension") ~ 1.0,
        status == "Doubtful" ~ 0.75,
        status == "Questionable" ~ 0.3,
        TRUE ~ 0.1
      ),
      
      # Calculate total impact
      total_impact = impact_value * severity_multiplier
    ) %>%
    select(
      team, player_name, position, position_group, status,
      injury = InjuryBodyPart,
      practice_status = PracticeStatus,
      impact_value, severity_multiplier, total_impact,
      updated = Updated
    )
  
  cat("✓ Processed", nrow(injuries_clean), "injuries\n")
  
  # Create team-level summary
  injury_summary <- injuries_clean %>%
    group_by(team) %>%
    summarise(
      total_injuries = n(),
      
      # Count by status
      players_out = sum(status == "Out"),
      players_doubtful = sum(status == "Doubtful"),
      players_questionable = sum(status == "Questionable"),
      players_ir = sum(status == "IR"),
      
      # Key position injuries
      qb_injured = sum(position == "QB" & status %in% c("Out", "Doubtful")),
      qb_questionable = sum(position == "QB" & status == "Questionable"),
      
      ol_injured = sum(position_group %in% c("OT", "OG") & status %in% c("Out", "Doubtful")),
      wr_injured = sum(position_group == "WR" & status %in% c("Out", "Doubtful")),
      rb_injured = sum(position_group == "RB" & status %in% c("Out", "Doubtful")),
      
      dl_injured = sum(position_group == "DL" & status %in% c("Out", "Doubtful")),
      lb_injured = sum(position_group == "LB" & status %in% c("Out", "Doubtful")),
      cb_injured = sum(position_group == "CB" & status %in% c("Out", "Doubtful")),
      
      # Total impact score
      total_impact_score = sum(total_impact, na.rm = TRUE),
      
      # Key injuries (high impact)
      key_injuries_out = sum(status %in% c("Out", "Doubtful", "IR") & impact_value >= 1.5),
      
      .groups = 'drop'
    )
  
  cat("✓ Created team summaries for", nrow(injury_summary), "teams\n")
  
  return(list(
    detailed = injuries_clean,
    summary = injury_summary
  ))
}

# ============================================================================
# FUNCTION: Add Injuries to Matchups
# ============================================================================

add_injuries_to_matchups <- function(matchups, injury_summary) {
  
  if (is.null(injury_summary) || nrow(injury_summary) == 0) {
    cat("No injury data to add\n")
    
    # Add empty injury columns
    matchups <- matchups %>%
      mutate(
        away_total_injuries = 0,
        away_players_out = 0,
        away_key_injuries_out = 0,
        away_qb_injured = 0,
        away_total_impact_score = 0,
        
        home_total_injuries = 0,
        home_players_out = 0,
        home_key_injuries_out = 0,
        home_qb_injured = 0,
        home_total_impact_score = 0,
        
        injury_advantage = 0
      )
    
    return(matchups)
  }
  
  cat("Adding injury data to matchups...\n")
  
  # Join injury data for away teams
  matchups <- matchups %>%
    left_join(
      injury_summary %>%
        rename_with(~paste0("away_", .), -team),
      by = c("away_team" = "team")
    ) %>%
    # Join injury data for home teams
    left_join(
      injury_summary %>%
        rename_with(~paste0("home_", .), -team),
      by = c("home_team" = "team")
    ) %>%
    # Replace NA with 0
    mutate(
      across(starts_with("away_") & where(is.numeric), ~replace_na(., 0)),
      across(starts_with("home_") & where(is.numeric), ~replace_na(., 0))
    ) %>%
    # Calculate injury advantage
    mutate(
      injury_advantage = home_total_impact_score - away_total_impact_score
    )
  
  cat("✓ Injury data added to", nrow(matchups), "matchups\n")
  
  return(matchups)
}

# ============================================================================
# MAIN WRAPPER FUNCTION
# ============================================================================

fetch_and_process_injuries <- function(season = 2025, week = NULL, 
                                       api_key = SPORTSDATA_API_KEY) {
  
  cat("\n")
  cat("╔══════════════════════════════════════════════════════════════╗\n")
  cat("║         FETCHING INJURY DATA FROM SPORTSDATA.IO             ║\n")
  cat("╚══════════════════════════════════════════════════════════════╝\n\n")
  
  # Fetch raw data
  raw_injuries <- fetch_injured_players(api_key)
  
  # Process data
  processed_injuries <- process_injury_data(raw_injuries, season, week)
  
  # Print summary
  if (nrow(processed_injuries$summary) > 0) {
    cat("\n📊 INJURY SUMMARY:\n")
    cat("════════════════════════════════════════════════════════════════\n")
    
    # Teams with most injuries
    top_injuries <- processed_injuries$summary %>%
      arrange(desc(total_impact_score)) %>%
      head(5)
    
    cat("\nTeams Most Impacted by Injuries:\n")
    for (i in 1:nrow(top_injuries)) {
      team <- top_injuries[i,]
      cat(sprintf("%d. %s - Impact: %.1f (Out: %d, Doubtful: %d, Key: %d)\n",
                  i, team$team, team$total_impact_score,
                  team$players_out, team$players_doubtful, team$key_injuries_out))
    }
    
    # QB injuries
    qb_issues <- processed_injuries$summary %>%
      filter(qb_injured > 0 | qb_questionable > 0)
    
    if (nrow(qb_issues) > 0) {
      cat("\n⚠️  Teams with QB Concerns:\n")
      for (i in 1:nrow(qb_issues)) {
        team <- qb_issues[i,]
        status <- ifelse(team$qb_injured > 0, "OUT/DOUBTFUL", "QUESTIONABLE")
        cat(sprintf("   • %s - %s\n", team$team, status))
      }
    }
  }
  
  cat("\n✅ Injury data fetch complete!\n")
  cat("════════════════════════════════════════════════════════════════\n\n")
  
  return(processed_injuries)
}

# ============================================================================
# EXAMPLE USAGE
# ============================================================================

if (FALSE) {
  # Run this to test the injury fetcher
  injury_data <- fetch_and_process_injuries(season = 2025, week = 11)
  
  # View detailed injuries
  View(injury_data$detailed)
  
  # View team summaries
  View(injury_data$summary)
  
  # Add to matchups (assuming you have a matchups dataframe)
  # matchups_with_injuries <- add_injuries_to_matchups(matchups, injury_data$summary)
}
