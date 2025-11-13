# ============================================================================
# NFL GAME WEATHER FETCHER
# ============================================================================
# Fetches real-time weather forecasts for NFL games
# Uses WeatherAPI.com (free tier: 1M calls/month)

# Load required packages
if (!require("httr")) install.packages("httr")
if (!require("jsonlite")) install.packages("jsonlite")
if (!require("dplyr")) install.packages("dplyr")
if (!require("lubridate")) install.packages("lubridate")

library(httr)
library(jsonlite)
library(dplyr)
library(lubridate)

# ============================================================================
# CONFIGURATION
# ============================================================================

# WeatherAPI.com API Key (FREE TIER - sign up at weatherapi.com)
# You'll need to register and get your own key - it's free!
WEATHER_API_KEY <- Sys.getenv("WEATHER_API_KEY", "YOUR_KEY_HERE")

# If API key not available, try to read from environment file
if (WEATHER_API_KEY == "YOUR_KEY_HERE") {
  env_file <- "C:/Users/Patsc/Documents/nflfastr/v2/nfl-model/config/.env"
  if (file.exists(env_file)) {
    env_lines <- readLines(env_file)
    weather_line <- grep("WEATHER_API_KEY", env_lines, value = TRUE)
    if (length(weather_line) > 0) {
      WEATHER_API_KEY <- sub(".*=\\s*", "", weather_line)
    }
  }
}

# Weather API endpoint
WEATHER_API_BASE <- "http://api.weatherapi.com/v1"

# Stadium information with coordinates
STADIUM_INFO <- tribble(
  ~team, ~stadium_name, ~lat, ~lon, ~is_dome, ~is_retractable,
  
  # Domes (No weather impact)
  "ATL", "Mercedes-Benz Stadium", 33.7554, -84.4009, TRUE, TRUE,
  "DET", "Ford Field", 42.3400, -83.0456, TRUE, FALSE,
  "HOU", "NRG Stadium", 29.6847, -95.4107, TRUE, TRUE,
  "IND", "Lucas Oil Stadium", 39.7601, -86.1639, TRUE, TRUE,
  "LAR", "SoFi Stadium", 33.9534, -118.3390, TRUE, FALSE,
  "LAC", "SoFi Stadium", 33.9534, -118.3390, TRUE, FALSE,
  "MIN", "U.S. Bank Stadium", 44.9737, -93.2577, TRUE, FALSE,
  "NO", "Caesars Superdome", 29.9511, -90.0812, TRUE, FALSE,
  "LV", "Allegiant Stadium", 36.0909, -115.1833, TRUE, FALSE,
  
  # Retractable (Weather dependent)
  "ARI", "State Farm Stadium", 33.5276, -112.2626, FALSE, TRUE,
  "DAL", "AT&T Stadium", 32.7473, -97.0945, FALSE, TRUE,
  "MIA", "Hard Rock Stadium", 25.9580, -80.2389, FALSE, TRUE,
  
  # Outdoor stadiums
  "BAL", "M&T Bank Stadium", 39.2780, -76.6227, FALSE, FALSE,
  "BUF", "Highmark Stadium", 42.7738, -78.7870, FALSE, FALSE,
  "CAR", "Bank of America Stadium", 35.2258, -80.8529, FALSE, FALSE,
  "CHI", "Soldier Field", 41.8623, -87.6167, FALSE, FALSE,
  "CIN", "Paycor Stadium", 39.0954, -84.5160, FALSE, FALSE,
  "CLE", "Cleveland Browns Stadium", 41.5061, -81.6995, FALSE, FALSE,
  "DEN", "Empower Field at Mile High", 39.7439, -105.0201, FALSE, FALSE,
  "GB", "Lambeau Field", 44.5013, -88.0622, FALSE, FALSE,
  "JAX", "TIAA Bank Field", 30.3240, -81.6373, FALSE, FALSE,
  "KC", "GEHA Field at Arrowhead", 39.0489, -94.4839, FALSE, FALSE,
  "NE", "Gillette Stadium", 42.0909, -71.2643, FALSE, FALSE,
  "NYG", "MetLife Stadium", 40.8128, -74.0742, FALSE, FALSE,
  "NYJ", "MetLife Stadium", 40.8128, -74.0742, FALSE, FALSE,
  "PHI", "Lincoln Financial Field", 39.9008, -75.1675, FALSE, FALSE,
  "PIT", "Acrisure Stadium", 40.4468, -80.0158, FALSE, FALSE,
  "SF", "Levi's Stadium", 37.4032, -121.9698, FALSE, FALSE,
  "SEA", "Lumen Field", 47.5952, -122.3316, FALSE, FALSE,
  "TB", "Raymond James Stadium", 27.9759, -82.5033, FALSE, FALSE,
  "TEN", "Nissan Stadium", 36.1665, -86.7713, FALSE, FALSE,
  "WAS", "Northwest Stadium", 38.9076, -76.8645, FALSE, FALSE
)

# ============================================================================
# FUNCTION: Fetch Weather for Stadium
# ============================================================================

fetch_stadium_weather <- function(lat, lon, game_datetime, api_key = WEATHER_API_KEY) {
  
  # Check if API key is valid
  if (is.null(api_key) || api_key == "" || api_key == "YOUR_KEY_HERE") {
    return(list(
      temp = NA,
      wind = NA,
      precip = NA,
      condition = "No API Key",
      error = TRUE
    ))
  }
  
  # Calculate days from now for forecast
  game_date <- as.Date(game_datetime)
  days_ahead <- as.numeric(difftime(game_date, Sys.Date(), units = "days"))
  
  # WeatherAPI.com free tier: 3 days forecast
  if (days_ahead > 3) {
    return(list(
      temp = NA,
      wind = NA,
      precip = NA,
      condition = "Beyond forecast range",
      error = TRUE
    ))
  }
  
  # Build request URL
  url <- paste0(WEATHER_API_BASE, "/forecast.json")
  
  # Make API request
  response <- tryCatch({
    GET(
      url,
      query = list(
        key = api_key,
        q = paste0(lat, ",", lon),
        days = max(1, ceiling(days_ahead) + 1),
        aqi = "no",
        alerts = "no"
      ),
      timeout(10)
    )
  }, error = function(e) {
    return(NULL)
  })
  
  # Check response
  if (is.null(response) || status_code(response) != 200) {
    return(list(
      temp = NA,
      wind = NA,
      precip = NA,
      condition = "API Error",
      error = TRUE
    ))
  }
  
  # Parse response
  weather_data <- tryCatch({
    content(response, "text") %>%
      fromJSON(flatten = TRUE)
  }, error = function(e) {
    return(NULL)
  })
  
  if (is.null(weather_data)) {
    return(list(
      temp = NA,
      wind = NA,
      precip = NA,
      condition = "Parse Error",
      error = TRUE
    ))
  }
  
  # Extract forecast for game day
  game_hour <- hour(game_datetime)
  
  # Find the right forecast day
  forecasts <- weather_data$forecast$forecastday
  target_date <- format(game_date, "%Y-%m-%d")
  
  day_forecast <- forecasts[forecasts$date == target_date, ]
  
  if (nrow(day_forecast) == 0) {
    # Use first available day if exact match not found
    day_forecast <- forecasts[1, ]
  }
  
  # Get hourly forecast closest to game time
  if (!is.null(day_forecast$hour[[1]])) {
    hourly <- day_forecast$hour[[1]]
    
    # Find hour closest to game time
    hour_diff <- abs(hourly$time_epoch - as.numeric(as.POSIXct(game_datetime)))
    closest_hour <- hourly[which.min(hour_diff), ]
    
    return(list(
      temp = closest_hour$temp_f,
      feels_like = closest_hour$feelslike_f,
      wind = closest_hour$wind_mph,
      wind_gust = closest_hour$gust_mph,
      precip_mm = closest_hour$precip_mm,
      precip_chance = closest_hour$chance_of_rain,
      humidity = closest_hour$humidity,
      condition = closest_hour$condition.text,
      error = FALSE
    ))
  } else {
    # Use day average if hourly not available
    return(list(
      temp = day_forecast$day$avgtemp_f,
      feels_like = day_forecast$day$avgtemp_f,
      wind = day_forecast$day$maxwind_mph,
      wind_gust = day_forecast$day$maxwind_mph,
      precip_mm = day_forecast$day$totalprecip_mm,
      precip_chance = day_forecast$day$daily_chance_of_rain,
      humidity = day_forecast$day$avghumidity,
      condition = day_forecast$day$condition.text,
      error = FALSE
    ))
  }
}

# ============================================================================
# FUNCTION: Get Weather for All Games
# ============================================================================

get_game_weather <- function(schedules, api_key = WEATHER_API_KEY) {
  
  cat("\n")
  cat("╔══════════════════════════════════════════════════════════════╗\n")
  cat("║              FETCHING WEATHER DATA FOR GAMES                ║\n")
  cat("╚══════════════════════════════════════════════════════════════╝\n\n")
  
  if (api_key == "YOUR_KEY_HERE" || is.null(api_key) || api_key == "") {
    cat("⚠️  WARNING: No Weather API key configured!\n")
    cat("   Sign up for free at https://www.weatherapi.com/\n")
    cat("   Add key to config/.env as: WEATHER_API_KEY=your_key_here\n\n")
    cat("   Using fallback: Stadium roof data only\n\n")
  }
  
  # Join with stadium info
  games_with_stadiums <- schedules %>%
    left_join(STADIUM_INFO, by = c("home_team" = "team"))
  
  # Initialize weather columns
  games_with_stadiums <- games_with_stadiums %>%
    mutate(
      weather_temp = NA_real_,
      weather_feels_like = NA_real_,
      weather_wind = NA_real_,
      weather_wind_gust = NA_real_,
      weather_precip_mm = NA_real_,
      weather_precip_chance = NA_real_,
      weather_humidity = NA_real_,
      weather_condition = NA_character_,
      weather_fetched = FALSE
    )
  
  # Fetch weather for each game
  for (i in 1:nrow(games_with_stadiums)) {
    game <- games_with_stadiums[i, ]
    
    cat(sprintf("[%d/%d] %s @ %s... ", 
                i, nrow(games_with_stadiums), 
                game$away_team, game$home_team))
    
    # Skip domes (unless retractable)
    if (game$is_dome && !game$is_retractable) {
      cat("DOME (no weather impact)\n")
      games_with_stadiums$weather_condition[i] <- "DOME"
      games_with_stadiums$weather_fetched[i] <- TRUE
      next
    }
    
    # Create game datetime
    game_datetime <- ymd_hm(paste(game$gameday, game$gametime))
    
    # Fetch weather
    weather <- fetch_stadium_weather(
      game$lat, 
      game$lon, 
      game_datetime,
      api_key
    )
    
    if (!weather$error) {
      games_with_stadiums$weather_temp[i] <- weather$temp
      games_with_stadiums$weather_feels_like[i] <- weather$feels_like
      games_with_stadiums$weather_wind[i] <- weather$wind
      games_with_stadiums$weather_wind_gust[i] <- weather$wind_gust
      games_with_stadiums$weather_precip_mm[i] <- weather$precip_mm
      games_with_stadiums$weather_precip_chance[i] <- weather$precip_chance
      games_with_stadiums$weather_humidity[i] <- weather$humidity
      games_with_stadiums$weather_condition[i] <- weather$condition
      games_with_stadiums$weather_fetched[i] <- TRUE
      
      cat(sprintf("%.0f°F, Wind: %.0f mph - %s\n", 
                  weather$temp, weather$wind, weather$condition))
    } else {
      cat(weather$condition, "\n")
    }
    
    # Rate limit: 1 call per second (free tier)
    Sys.sleep(1)
  }
  
  # Calculate weather impact scores
  games_with_weather <- games_with_stadiums %>%
    mutate(
      # Temperature impact
      is_cold = !is.na(weather_temp) & weather_temp < 40,
      is_very_cold = !is.na(weather_temp) & weather_temp < 20,
      is_hot = !is.na(weather_temp) & weather_temp > 85,
      
      # Wind impact
      is_windy = !is.na(weather_wind) & weather_wind > 15,
      is_very_windy = !is.na(weather_wind) & weather_wind > 20,
      
      # Precipitation impact
      is_rainy = !is.na(weather_precip_chance) & weather_precip_chance > 50,
      is_very_rainy = !is.na(weather_precip_mm) & weather_precip_mm > 5,
      
      # Composite weather impact score (0-5 scale)
      weather_impact_score = case_when(
        weather_condition == "DOME" ~ 0,
        is.na(weather_temp) ~ 0,
        
        # Severe conditions (4-5 points)
        (is_very_cold & is_very_windy) ~ 5,
        (is_very_windy & is_very_rainy) ~ 5,
        (is_very_cold & is_windy) ~ 4,
        is_very_windy ~ 4,
        
        # Moderate conditions (2-3 points)
        (is_cold & is_windy) ~ 3,
        (is_windy & is_rainy) ~ 3,
        is_windy ~ 2,
        is_cold ~ 2,
        is_very_rainy ~ 2,
        
        # Minor conditions (1 point)
        is_hot ~ 1,
        is_rainy ~ 1,
        
        # Good conditions
        TRUE ~ 0
      ),
      
      # Point adjustment for predictions
      weather_point_adjustment = case_when(
        weather_impact_score >= 5 ~ -3.0,
        weather_impact_score >= 4 ~ -2.0,
        weather_impact_score >= 3 ~ -1.5,
        weather_impact_score >= 2 ~ -1.0,
        weather_impact_score >= 1 ~ -0.5,
        TRUE ~ 0
      )
    )
  
  # Summary
  cat("\n📊 WEATHER SUMMARY:\n")
  cat("════════════════════════════════════════════════════════════════\n")
  
  dome_games <- sum(games_with_weather$weather_condition == "DOME", na.rm = TRUE)
  outdoor_games <- nrow(games_with_weather) - dome_games
  cold_games <- sum(games_with_weather$is_cold, na.rm = TRUE)
  windy_games <- sum(games_with_weather$is_windy, na.rm = TRUE)
  rainy_games <- sum(games_with_weather$is_rainy, na.rm = TRUE)
  
  cat(sprintf("  Total games: %d\n", nrow(games_with_weather)))
  cat(sprintf("  Dome games: %d\n", dome_games))
  cat(sprintf("  Outdoor games: %d\n", outdoor_games))
  cat(sprintf("  Cold weather games (<40°F): %d\n", cold_games))
  cat(sprintf("  Windy games (>15mph): %d\n", windy_games))
  cat(sprintf("  Rainy games (>50%% chance): %d\n", rainy_games))
  
  # Highlight worst weather games
  worst_weather <- games_with_weather %>%
    filter(weather_impact_score >= 3) %>%
    arrange(desc(weather_impact_score)) %>%
    select(away_team, home_team, weather_temp, weather_wind, 
           weather_condition, weather_impact_score)
  
  if (nrow(worst_weather) > 0) {
    cat("\n⚠️  GAMES WITH SIGNIFICANT WEATHER IMPACT:\n")
    for (i in 1:nrow(worst_weather)) {
      game <- worst_weather[i,]
      cat(sprintf("   %s @ %s - %.0f°F, %.0f mph wind - Impact: %d/5\n",
                  game$away_team, game$home_team, 
                  game$weather_temp, game$weather_wind,
                  game$weather_impact_score))
    }
  }
  
  cat("\n✅ Weather data fetch complete!\n")
  cat("════════════════════════════════════════════════════════════════\n\n")
  
  return(games_with_weather)
}

# ============================================================================
# EXAMPLE USAGE
# ============================================================================

if (FALSE) {
  # Test the weather fetcher
  
  # Load schedule for current week
  library(nflreadr)
  schedules <- load_schedules(2025) %>%
    filter(week == 11)
  
  # Fetch weather
  games_with_weather <- get_game_weather(schedules)
  
  # View results
  View(games_with_weather %>%
         select(away_team, home_team, weather_temp, weather_wind,
                weather_condition, weather_impact_score))
}
