# ============================================================================
# NFL BETTING MODEL - INTERACTIVE SHINY DASHBOARD V3 (FIXED COLUMN NAMES)
# ============================================================================
# Now using YOUR actual column names from the diagnostic!

library(shiny)
library(shinydashboard)
library(shinyWidgets)
library(dplyr)
library(tidyr)
library(ggplot2)
library(DT)
library(scales)
library(plotly)

# Try to load NFL packages
nfl_packages_available <- FALSE
tryCatch({
  library(nflreadr)
  library(nflplotR)
  nfl_packages_available <- TRUE
}, error = function(e) {
  warning("NFL packages not available. Team logos may not display.")
})

# ============================================================================
# CONFIGURATION
# ============================================================================

SEASON <- 2025
WEEK <- 9
BASE_DIR <- 'C:/Users/Patsc/Documents/nfl'

# ============================================================================
# LOAD DATA FUNCTION WITH CORRECT COLUMN NAMES
# ============================================================================

load_nfl_data <- function() {
  
  data_list <- list()
  
  # Load team visual data
  if (nfl_packages_available) {
    tryCatch({
      data_list$teams <- nflreadr::load_teams() %>%
        select(team_abbr, team_name, team_color, team_color2, 
               team_logo_espn, team_wordmark, team_conf, team_division)
      cat("✓ Loaded team data:", nrow(data_list$teams), "teams\n")
    }, error = function(e) {
      cat("⚠ Could not load team data:", e$message, "\n")
      data_list$teams <- NULL
    })
  } else {
    data_list$teams <- NULL
  }
  
  # Set up directories
  matchup_dir <- file.path(BASE_DIR, paste0('week', WEEK), 'matchup_analysis')
  odds_dir <- file.path(BASE_DIR, paste0('week', WEEK), 'odds_analysis')
  week_dir <- file.path(BASE_DIR, paste0('week', WEEK))
  
  # Load matchup summary
  tryCatch({
    enhanced_file <- file.path(matchup_dir, "matchup_summary_enhanced.csv")
    standard_file <- file.path(matchup_dir, "matchup_summary.csv")
    
    if (file.exists(enhanced_file)) {
      data_list$matchups <- read.csv(enhanced_file, stringsAsFactors = FALSE)
      data_list$data_type <- "Enhanced"
      cat("✓ Loaded enhanced matchup data:", nrow(data_list$matchups), "games\n")
    } else if (file.exists(standard_file)) {
      data_list$matchups <- read.csv(standard_file, stringsAsFactors = FALSE)
      data_list$data_type <- "Standard"
      cat("✓ Loaded standard matchup data:", nrow(data_list$matchups), "games\n")
    } else {
      cat("⚠ No matchup data found\n")
      data_list$matchups <- NULL
      data_list$data_type <- "None"
    }
  }, error = function(e) {
    cat("⚠ Error loading matchup data:", e$message, "\n")
    data_list$matchups <- NULL
    data_list$data_type <- "None"
  })
  
  # Load betting data
  tryCatch({
    betting_file <- file.path(odds_dir, "profitable_bets.csv")
    if (file.exists(betting_file)) {
      data_list$betting <- read.csv(betting_file, stringsAsFactors = FALSE)
      cat("✓ Loaded betting data:", nrow(data_list$betting), "bets\n")
    } else {
      cat("⚠ No betting data found\n")
      data_list$betting <- NULL
    }
  }, error = function(e) {
    cat("⚠ Error loading betting data:", e$message, "\n")
    data_list$betting <- NULL
  })
  
  # Load all games analysis
  tryCatch({
    all_games_file <- file.path(odds_dir, "all_games_analysis.csv")
    if (file.exists(all_games_file)) {
      data_list$all_games <- read.csv(all_games_file, stringsAsFactors = FALSE)
      cat("✓ Loaded all games data:", nrow(data_list$all_games), "games\n")
    } else {
      cat("⚠ No all games data found\n")
      data_list$all_games <- NULL
    }
  }, error = function(e) {
    cat("⚠ Error loading all games data:", e$message, "\n")
    data_list$all_games <- NULL
  })
  
  # Load offense rankings - FILTER TO CURRENT WEEK ONLY
  tryCatch({
    offense_file <- file.path(week_dir, "offense_weekly.csv")
    if (file.exists(offense_file)) {
      data_list$offense <- read.csv(offense_file, stringsAsFactors = FALSE) %>%
        filter(week == !!WEEK) %>%  # FILTER TO CURRENT WEEK!
        rename(
          avg_epa = avg_epa_per_play,    # Map to expected name
          pass_epa = avg_epa_pass,        # Map to expected name
          rush_epa = avg_epa_run          # Map to expected name
        )
      cat("✓ Loaded offense data:", nrow(data_list$offense), "teams (Week", WEEK, ")\n")
    } else {
      cat("⚠ No offense data found at:", offense_file, "\n")
      data_list$offense <- NULL
    }
  }, error = function(e) {
    cat("⚠ Error loading offense data:", e$message, "\n")
    data_list$offense <- NULL
  })
  
  # Load defense rankings - FILTER TO CURRENT WEEK ONLY
  tryCatch({
    defense_file <- file.path(week_dir, "defense_weekly.csv")
    if (file.exists(defense_file)) {
      data_list$defense <- read.csv(defense_file, stringsAsFactors = FALSE) %>%
        filter(week == !!WEEK) %>%  # FILTER TO CURRENT WEEK!
        rename(
          avg_epa_allowed = def_avg_epa_per_play  # Map to expected name
        )
      cat("✓ Loaded defense data:", nrow(data_list$defense), "teams (Week", WEEK, ")\n")
    } else {
      cat("⚠ No defense data found at:", defense_file, "\n")
      data_list$defense <- NULL
    }
  }, error = function(e) {
    cat("⚠ Error loading defense data:", e$message, "\n")
    data_list$defense <- NULL
  })
  
  return(data_list)
}

# ============================================================================
# UI
# ============================================================================

ui <- dashboardPage(
  skin = "blue",
  
  dashboardHeader(
    title = span(
      "🏈 NFL Betting Dashboard",
      style = "font-weight: bold; font-size: 20px;"
    ),
    titleWidth = 300
  ),
  
  dashboardSidebar(
    width = 300,
    sidebarMenu(
      menuItem("📊 Dashboard Overview", tabName = "overview", icon = icon("dashboard")),
      menuItem("🎯 Top Picks", tabName = "picks", icon = icon("star")),
      menuItem("📈 All Matchups", tabName = "matchups", icon = icon("table")),
      menuItem("🔥 Power Rankings", tabName = "rankings", icon = icon("chart-bar")),
      menuItem("⚙️ Team Analysis", tabName = "teams", icon = icon("users"))
    ),
    hr(),
    div(
      style = "padding: 15px;",
      h4(paste("Week", WEEK), style = "color: white; text-align: center;"),
      h5(paste("Season", SEASON), style = "color: #aaa; text-align: center;")
    )
  ),
  
  dashboardBody(
    
    tags$head(
      tags$style(HTML("
        .content-wrapper { background-color: #f4f6f9; }
        .box { border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .small-box { border-radius: 5px; }
        .small-box h3 { font-size: 32px; font-weight: bold; }
        .value-box { 
          padding: 10px; 
          border-radius: 5px; 
          margin: 5px 0;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          color: white;
        }
        .elite-bet { background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%) !important; }
        .strong-bet { background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%) !important; }
        .good-bet { background: linear-gradient(135deg, #43e97b 0%, #38f9d7 100%) !important; }
      "))
    ),
    
    tabItems(
      
      # ===== OVERVIEW TAB =====
      tabItem(
        tabName = "overview",
        
        fluidRow(
          valueBoxOutput("total_games_box", width = 3),
          valueBoxOutput("value_bets_box", width = 3),
          valueBoxOutput("elite_bets_box", width = 3),
          valueBoxOutput("avg_edge_box", width = 3)
        ),
        
        fluidRow(
          box(
            title = "Model Edge vs Vegas Lines",
            status = "primary",
            solidHeader = TRUE,
            width = 12,
            plotlyOutput("edge_chart", height = "500px")
          )
        ),
        
        fluidRow(
          box(
            title = "Week Overview - Best Matchups",
            status = "info",
            solidHeader = TRUE,
            width = 12,
            plotlyOutput("matchup_overview", height = "400px")
          )
        )
      ),
      
      # ===== TOP PICKS TAB =====
      tabItem(
        tabName = "picks",
        
        fluidRow(
          box(
            title = "🎯 VALUE BETTING OPPORTUNITIES",
            status = "warning",
            solidHeader = TRUE,
            width = 12,
            uiOutput("top_picks_cards")
          )
        ),
        
        fluidRow(
          box(
            title = "Betting Recommendations Detail",
            status = "primary",
            solidHeader = TRUE,
            width = 12,
            DTOutput("picks_table")
          )
        )
      ),
      
      # ===== ALL MATCHUPS TAB =====
      tabItem(
        tabName = "matchups",
        
        fluidRow(
          box(
            title = "All Week Matchups",
            status = "primary",
            solidHeader = TRUE,
            width = 12,
            DTOutput("matchups_table")
          )
        ),
        
        fluidRow(
          box(
            title = "Game Details with Context",
            status = "info",
            solidHeader = TRUE,
            width = 12,
            uiOutput("game_details")
          )
        )
      ),
      
      # ===== POWER RANKINGS TAB =====
      tabItem(
        tabName = "rankings",
        
        fluidRow(
          box(
            title = "Offensive Power Rankings",
            status = "success",
            solidHeader = TRUE,
            width = 6,
            plotlyOutput("offense_rankings", height = "600px")
          ),
          
          box(
            title = "Defensive Power Rankings",
            status = "danger",
            solidHeader = TRUE,
            width = 6,
            plotlyOutput("defense_rankings", height = "600px")
          )
        ),
        
        fluidRow(
          box(
            title = "Efficiency Matrix",
            status = "primary",
            solidHeader = TRUE,
            width = 12,
            plotlyOutput("efficiency_matrix", height = "600px")
          )
        )
      ),
      
      # ===== TEAM ANALYSIS TAB =====
      tabItem(
        tabName = "teams",
        
        fluidRow(
          box(
            title = "Select Teams to Compare",
            status = "primary",
            solidHeader = TRUE,
            width = 12,
            fluidRow(
              column(6, selectInput("team1", "Team 1:", choices = NULL)),
              column(6, selectInput("team2", "Team 2:", choices = NULL))
            )
          )
        ),
        
        fluidRow(
          box(
            title = "Team Comparison",
            status = "info",
            solidHeader = TRUE,
            width = 12,
            plotlyOutput("team_comparison", height = "500px")
          )
        ),
        
        fluidRow(
          box(
            title = "Detailed Team Stats",
            status = "primary",
            solidHeader = TRUE,
            width = 12,
            DTOutput("team_stats_table")
          )
        )
      )
    )
  )
)

# ============================================================================
# SERVER
# ============================================================================

server <- function(input, output, session) {
  
  # Load data reactively
  nfl_data <- reactive({
    cat("\n=== Loading NFL Data ===\n")
    data <- load_nfl_data()
    
    # Update team selection choices
    if (!is.null(data$offense) && "offense_team" %in% names(data$offense)) {
      teams <- unique(data$offense$offense_team)
      teams <- teams[!is.na(teams)]
      
      if (!is.null(data$teams)) {
        team_choices <- setNames(teams, sapply(teams, function(x) {
          team_name <- data$teams$team_name[data$teams$team_abbr == x]
          if (length(team_name) > 0) return(team_name[1]) else return(x)
        }))
      } else {
        team_choices <- setNames(teams, teams)
      }
      
      updateSelectInput(session, "team1", choices = team_choices, selected = teams[1])
      updateSelectInput(session, "team2", choices = team_choices, selected = teams[min(2, length(teams))])
    }
    
    cat("=== Data Loading Complete ===\n\n")
    return(data)
  })
  
  # ===== VALUE BOXES =====
  
  output$total_games_box <- renderValueBox({
    data <- nfl_data()
    n_games <- if (!is.null(data$all_games)) nrow(data$all_games) else 0
    
    valueBox(
      n_games,
      "Games Analyzed",
      icon = icon("football-ball"),
      color = "blue"
    )
  })
  
  output$value_bets_box <- renderValueBox({
    data <- nfl_data()
    n_bets <- if (!is.null(data$betting)) nrow(data$betting) else 0
    
    valueBox(
      n_bets,
      "Value Bets Found",
      icon = icon("chart-line"),
      color = "green"
    )
  })
  
  output$elite_bets_box <- renderValueBox({
    data <- nfl_data()
    n_elite <- if (!is.null(data$betting)) {
      sum(grepl("ELITE", data$betting$ev_tier), na.rm = TRUE)
    } else {
      0
    }
    
    valueBox(
      n_elite,
      "Elite Opportunities",
      icon = icon("fire"),
      color = "red"
    )
  })
  
  output$avg_edge_box <- renderValueBox({
    data <- nfl_data()
    avg_edge <- if (!is.null(data$betting) && nrow(data$betting) > 0) {
      mean(abs(data$betting$edge), na.rm = TRUE)
    } else {
      0
    }
    
    valueBox(
      sprintf("%.1f pts", avg_edge),
      "Average Edge",
      icon = icon("bullseye"),
      color = "purple"
    )
  })
  
  # ===== EDGE CHART =====
  
  output$edge_chart <- renderPlotly({
    data <- nfl_data()
    
    if (is.null(data$all_games) || nrow(data$all_games) == 0) {
      return(plot_ly() %>% 
               add_text(x = 0.5, y = 0.5, text = "No data available", 
                        textfont = list(size = 20, color = "gray")))
    }
    
    plot_data <- data$all_games %>%
      mutate(
        edge = as.numeric(edge),
        abs_edge = abs(edge),
        has_value = abs_edge >= 1.5
      ) %>%
      arrange(desc(abs(edge))) %>%
      head(12) %>%
      mutate(
        color = case_when(
          grepl("ELITE", ev_tier) ~ "#e74c3c",
          grepl("STRONG", ev_tier) ~ "#3498db",
          grepl("GOOD", ev_tier) ~ "#2ecc71",
          TRUE ~ "#95a5a6"
        )
      )
    
    plot_ly(plot_data, 
            x = ~edge, 
            y = ~reorder(matchup_key, edge),
            type = "bar",
            marker = list(color = ~color),
            text = ~paste0(ev_tier, "<br>Edge: ", sprintf("%.1f", edge), " pts<br>",
                           "Vegas: ", sprintf("%.1f", vegas_line), "<br>",
                           "Model: ", sprintf("%.1f", model_line)),
            hoverinfo = "text") %>%
      layout(
        title = paste("Week", WEEK, "- Model vs Vegas Spreads"),
        xaxis = list(title = "Edge (Model - Vegas)", zeroline = TRUE),
        yaxis = list(title = ""),
        showlegend = FALSE,
        margin = list(l = 150)
      ) %>%
      add_segments(x = -1.5, xend = -1.5, y = 0, yend = nrow(plot_data) + 1,
                   line = list(color = "red", dash = "dash", width = 2),
                   showlegend = FALSE) %>%
      add_segments(x = 1.5, xend = 1.5, y = 0, yend = nrow(plot_data) + 1,
                   line = list(color = "red", dash = "dash", width = 2),
                   showlegend = FALSE)
  })
  
  # ===== MATCHUP OVERVIEW =====
  
  output$matchup_overview <- renderPlotly({
    data <- nfl_data()
    
    if (is.null(data$matchups) || nrow(data$matchups) == 0) {
      return(plot_ly() %>% 
               add_text(x = 0.5, y = 0.5, text = "No matchup data available", 
                        textfont = list(size = 20, color = "gray")))
    }
    
    plot_data <- data$matchups %>%
      mutate(
        net_home_advantage = as.numeric(net_home_advantage),
        game_label = paste0(away_team, " @ ", home_team)
      ) %>%
      arrange(desc(abs(net_home_advantage))) %>%
      head(10)
    
    plot_ly(plot_data,
            x = ~net_home_advantage,
            y = ~reorder(game_label, net_home_advantage),
            type = "bar",
            marker = list(
              color = ~ifelse(net_home_advantage > 0, "#2ecc71", "#e74c3c")
            ),
            text = ~paste0("Advantage: ", sprintf("%.3f", net_home_advantage), " EPA<br>",
                           "Projected Margin: ", sprintf("%.1f", projected_margin)),
            hoverinfo = "text") %>%
      layout(
        title = "Net EPA Advantage (Home Team Perspective)",
        xaxis = list(title = "EPA Advantage", zeroline = TRUE),
        yaxis = list(title = ""),
        showlegend = FALSE
      )
  })
  
  # ===== TOP PICKS CARDS =====
  
  output$top_picks_cards <- renderUI({
    data <- nfl_data()
    
    if (is.null(data$betting) || nrow(data$betting) == 0) {
      return(div(
        style = "text-align: center; padding: 50px;",
        h3("No value bets found this week", style = "color: #95a5a6;"),
        p("The model and Vegas are in close agreement.")
      ))
    }
    
    picks <- data$betting %>%
      arrange(desc(abs(edge))) %>%
      head(5)
    
    cards <- lapply(1:nrow(picks), function(i) {
      pick <- picks[i, ]
      
      card_class <- case_when(
        grepl("ELITE", pick$ev_tier) ~ "elite-bet",
        grepl("STRONG", pick$ev_tier) ~ "strong-bet",
        grepl("GOOD", pick$ev_tier) ~ "good-bet",
        TRUE ~ "value-box"
      )
      
      context <- ""
      if ("weather_impact" %in% names(pick) && !is.na(pick$weather_impact) && pick$weather_impact > 0) {
        context <- paste0(context, "⛈️ Weather Impact: ", pick$weather_impact, "/3 ")
      }
      if ("is_thursday" %in% names(pick) && !is.na(pick$is_thursday) && pick$is_thursday) {
        context <- paste0(context, "📅 Thursday Game ")
      }
      
      div(
        class = paste("value-box", card_class),
        style = "margin: 10px 0; padding: 15px;",
        h3(pick$ev_tier, style = "margin-top: 0;"),
        h4(pick$matchup_key, style = "margin: 5px 0;"),
        p(strong(pick$bet_recommendation), style = "font-size: 16px; margin: 10px 0;"),
        p(
          sprintf("Edge: %.1f pts | Vegas: %.1f | Model: %.1f", 
                  pick$edge, pick$vegas_line, pick$model_line),
          style = "margin: 5px 0;"
        ),
        p(sprintf("Confidence: %s | %s", pick$confidence, pick$sportsbook), 
          style = "margin: 5px 0;"),
        if (context != "") p(context, style = "margin: 5px 0; font-style: italic;") else NULL
      )
    })
    
    do.call(tagList, cards)
  })
  
  # ===== PICKS TABLE =====
  
  output$picks_table <- renderDT({
    data <- nfl_data()
    
    if (is.null(data$betting)) {
      return(datatable(data.frame(Message = "No data available")))
    }
    
    display_data <- data$betting %>%
      select(
        Tier = ev_tier,
        Matchup = matchup_key,
        Recommendation = bet_recommendation,
        Edge = edge,
        Vegas = vegas_line,
        Model = model_line,
        Confidence = confidence,
        Sportsbook = sportsbook
      ) %>%
      mutate(
        Edge = sprintf("%.1f", as.numeric(Edge)),
        Vegas = sprintf("%.1f", as.numeric(Vegas)),
        Model = sprintf("%.1f", as.numeric(Model))
      )
    
    datatable(
      display_data,
      options = list(
        pageLength = 10,
        dom = 'Bfrtip',
        scrollX = TRUE
      ),
      rownames = FALSE,
      class = 'cell-border stripe'
    ) %>%
      formatStyle(
        'Tier',
        backgroundColor = styleEqual(
          c('🔥 ELITE', '⭐ STRONG', '✓ GOOD'),
          c('#e74c3c', '#3498db', '#2ecc71')
        ),
        color = 'white',
        fontWeight = 'bold'
      )
  })
  
  # ===== MATCHUPS TABLE =====
  
  output$matchups_table <- renderDT({
    data <- nfl_data()
    
    if (is.null(data$matchups)) {
      return(datatable(data.frame(Message = "No data available")))
    }
    
    display_data <- data$matchups %>%
      select(
        Game = game,
        `Proj Margin` = projected_margin,
        `Proj Total` = projected_total,
        `Home EPA` = home_base_epa,
        `Away EPA` = away_base_epa,
        `Net Adv` = net_home_advantage
      ) %>%
      mutate(
        `Proj Margin` = sprintf("%.1f", as.numeric(`Proj Margin`)),
        `Proj Total` = sprintf("%.1f", as.numeric(`Proj Total`)),
        `Home EPA` = sprintf("%.3f", as.numeric(`Home EPA`)),
        `Away EPA` = sprintf("%.3f", as.numeric(`Away EPA`)),
        `Net Adv` = sprintf("%.3f", as.numeric(`Net Adv`))
      )
    
    datatable(
      display_data,
      options = list(
        pageLength = 15,
        dom = 'Bfrtip',
        scrollX = TRUE
      ),
      rownames = FALSE,
      class = 'cell-border stripe'
    )
  })
  
  # ===== GAME DETAILS =====
  
  output$game_details <- renderUI({
    data <- nfl_data()
    
    if (is.null(data$matchups)) {
      return(div(
        style = "text-align: center; padding: 30px;",
        h4("No matchup details available", style = "color: #95a5a6;")
      ))
    }
    
    details <- lapply(1:min(5, nrow(data$matchups)), function(i) {
      game <- data$matchups[i, ]
      
      div(
        style = "background: white; padding: 20px; margin: 10px 0; border-radius: 5px; border-left: 4px solid #3498db;",
        h4(game$game, style = "margin-top: 0; color: #2c3e50;"),
        p(
          strong("Projected Margin: "),
          sprintf("%.1f points (favoring %s)", 
                  abs(as.numeric(game$projected_margin)),
                  if_else(as.numeric(game$projected_margin) > 0, game$home_team, game$away_team))
        ),
        p(strong("Projected Total: "), sprintf("%.1f points", as.numeric(game$projected_total))),
        p(strong("Net EPA Advantage: "), sprintf("%.3f", as.numeric(game$net_home_advantage))),
        if ("weather_impact" %in% names(game) && !is.na(game$weather_impact) && game$weather_impact > 0) {
          p("⛈️ Weather Impact: ", game$weather_impact, "/3", style = "color: #e74c3c;")
        } else {
          NULL
        },
        if ("is_thursday" %in% names(game) && !is.na(game$is_thursday) && game$is_thursday) {
          p("📅 Thursday Night Game", style = "color: #f39c12;")
        } else {
          NULL
        }
      )
    })
    
    do.call(tagList, details)
  })
  
  # ===== POWER RANKINGS - OFFENSE =====
  
  output$offense_rankings <- renderPlotly({
    data <- nfl_data()
    
    if (is.null(data$offense) || nrow(data$offense) == 0) {
      return(plot_ly() %>% 
               add_text(x = 0.5, y = 0.5, 
                        text = "No offense data available", 
                        textfont = list(size = 16, color = "gray")))
    }
    
    plot_data <- data$offense %>%
      mutate(avg_epa = as.numeric(avg_epa)) %>%
      filter(!is.na(avg_epa)) %>%
      arrange(desc(avg_epa)) %>%
      head(16)
    
    # Join with team colors if available
    if (!is.null(data$teams)) {
      plot_data <- plot_data %>%
        left_join(data$teams, by = c("offense_team" = "team_abbr"))
      
      colors <- ifelse(is.na(plot_data$team_color), "#0066CC", plot_data$team_color)
      hover_text <- ifelse(
        is.na(plot_data$team_name),
        paste0(plot_data$offense_team, "<br>EPA/Play: ", sprintf("%.3f", plot_data$avg_epa)),
        paste0(plot_data$team_name, "<br>EPA/Play: ", sprintf("%.3f", plot_data$avg_epa))
      )
    } else {
      colors <- "#0066CC"
      hover_text <- paste0(plot_data$offense_team, "<br>EPA/Play: ", sprintf("%.3f", plot_data$avg_epa))
    }
    
    plot_ly(plot_data,
            x = ~avg_epa,
            y = ~reorder(offense_team, avg_epa),
            type = "bar",
            marker = list(color = colors),
            text = hover_text,
            hoverinfo = "text") %>%
      layout(
        title = "Top Offenses by EPA/Play",
        xaxis = list(title = "EPA per Play"),
        yaxis = list(title = ""),
        showlegend = FALSE,
        margin = list(l = 100)
      )
  })
  
  # ===== POWER RANKINGS - DEFENSE =====
  
  output$defense_rankings <- renderPlotly({
    data <- nfl_data()
    
    if (is.null(data$defense) || nrow(data$defense) == 0) {
      return(plot_ly() %>% 
               add_text(x = 0.5, y = 0.5, 
                        text = "No defense data available", 
                        textfont = list(size = 16, color = "gray")))
    }
    
    plot_data <- data$defense %>%
      mutate(avg_epa_allowed = as.numeric(avg_epa_allowed)) %>%
      filter(!is.na(avg_epa_allowed)) %>%
      arrange(avg_epa_allowed) %>%
      head(16)
    
    # Join with team colors if available
    if (!is.null(data$teams)) {
      plot_data <- plot_data %>%
        left_join(data$teams, by = c("defense_team" = "team_abbr"))
      
      colors <- ifelse(is.na(plot_data$team_color), "#e74c3c", plot_data$team_color)
      hover_text <- ifelse(
        is.na(plot_data$team_name),
        paste0(plot_data$defense_team, "<br>EPA/Play Allowed: ", sprintf("%.3f", plot_data$avg_epa_allowed)),
        paste0(plot_data$team_name, "<br>EPA/Play Allowed: ", sprintf("%.3f", plot_data$avg_epa_allowed))
      )
    } else {
      colors <- "#e74c3c"
      hover_text <- paste0(plot_data$defense_team, "<br>EPA/Play Allowed: ", sprintf("%.3f", plot_data$avg_epa_allowed))
    }
    
    plot_ly(plot_data,
            x = ~avg_epa_allowed,
            y = ~reorder(defense_team, -avg_epa_allowed),
            type = "bar",
            marker = list(color = colors),
            text = hover_text,
            hoverinfo = "text") %>%
      layout(
        title = "Top Defenses by EPA/Play Allowed",
        xaxis = list(title = "EPA per Play Allowed (Lower is Better)"),
        yaxis = list(title = ""),
        showlegend = FALSE,
        margin = list(l = 100)
      )
  })
  
  # ===== EFFICIENCY MATRIX =====
  
  output$efficiency_matrix <- renderPlotly({
    data <- nfl_data()
    
    if (is.null(data$offense) || is.null(data$defense)) {
      return(plot_ly() %>% 
               add_text(x = 0.5, y = 0.5, 
                        text = "Need both offense and defense data", 
                        textfont = list(size = 16, color = "gray")))
    }
    
    plot_data <- data$offense %>%
      select(team = offense_team, off_epa = avg_epa) %>%
      mutate(off_epa = as.numeric(off_epa)) %>%
      left_join(
        data$defense %>% 
          select(team = defense_team, def_epa = avg_epa_allowed) %>%
          mutate(def_epa = as.numeric(def_epa)),
        by = "team"
      ) %>%
      filter(!is.na(off_epa), !is.na(def_epa))
    
    # Add team info if available
    if (!is.null(data$teams)) {
      plot_data <- plot_data %>%
        left_join(data$teams, by = c("team" = "team_abbr"))
      
      colors <- ifelse(is.na(plot_data$team_color), "#3498db", plot_data$team_color)
      hover_text <- ifelse(
        is.na(plot_data$team_name),
        paste0(plot_data$team, "<br>Offensive EPA: ", sprintf("%.3f", plot_data$off_epa), 
               "<br>Defensive EPA: ", sprintf("%.3f", plot_data$def_epa)),
        paste0(plot_data$team_name, "<br>Offensive EPA: ", sprintf("%.3f", plot_data$off_epa), 
               "<br>Defensive EPA: ", sprintf("%.3f", plot_data$def_epa))
      )
    } else {
      colors <- "#3498db"
      hover_text <- paste0(plot_data$team, "<br>Offensive EPA: ", sprintf("%.3f", plot_data$off_epa), 
                           "<br>Defensive EPA: ", sprintf("%.3f", plot_data$def_epa))
    }
    
    plot_ly(plot_data,
            x = ~off_epa,
            y = ~def_epa,
            type = "scatter",
            mode = "markers+text",
            marker = list(
              size = 12,
              color = colors,
              line = list(color = "white", width = 2)
            ),
            text = ~team,
            textposition = "middle center",
            textfont = list(color = "white", size = 9, family = "Arial Black"),
            hovertext = hover_text,
            hoverinfo = "text") %>%
      layout(
        title = "Team Efficiency Matrix",
        xaxis = list(title = "Offensive EPA/Play (Better →)", zeroline = TRUE),
        yaxis = list(title = "Defensive EPA/Play Allowed (← Better)", zeroline = TRUE),
        showlegend = FALSE
      )
  })
  
  # ===== TEAM COMPARISON =====
  
  output$team_comparison <- renderPlotly({
    data <- nfl_data()
    
    req(input$team1, input$team2)
    
    if (is.null(data$offense) || is.null(data$defense)) {
      return(plot_ly() %>% 
               add_text(x = 0.5, y = 0.5, text = "No team data available"))
    }
    
    team1_off <- data$offense %>% filter(offense_team == input$team1)
    team2_off <- data$offense %>% filter(offense_team == input$team2)
    team1_def <- data$defense %>% filter(defense_team == input$team1)
    team2_def <- data$defense %>% filter(defense_team == input$team2)
    
    if (nrow(team1_off) == 0 || nrow(team2_off) == 0) {
      return(plot_ly() %>% 
               add_text(x = 0.5, y = 0.5, text = "Team data not available"))
    }
    
    # Build comparison data
    comp_data <- data.frame(
      Metric = c("Offensive EPA", "Pass EPA", "Rush EPA", "Defensive EPA"),
      Team1 = c(
        as.numeric(team1_off$avg_epa[1]),
        as.numeric(team1_off$pass_epa[1]),
        as.numeric(team1_off$rush_epa[1]),
        if (nrow(team1_def) > 0) as.numeric(team1_def$avg_epa_allowed[1]) else NA
      ),
      Team2 = c(
        as.numeric(team2_off$avg_epa[1]),
        as.numeric(team2_off$pass_epa[1]),
        as.numeric(team2_off$rush_epa[1]),
        if (nrow(team2_def) > 0) as.numeric(team2_def$avg_epa_allowed[1]) else NA
      )
    )
    
    # Get team colors if available
    team1_color <- "#0066CC"
    team2_color <- "#CC0000"
    if (!is.null(data$teams)) {
      tc1 <- data$teams %>% filter(team_abbr == input$team1) %>% pull(team_color)
      tc2 <- data$teams %>% filter(team_abbr == input$team2) %>% pull(team_color)
      if (length(tc1) > 0 && !is.na(tc1[1])) team1_color <- tc1[1]
      if (length(tc2) > 0 && !is.na(tc2[1])) team2_color <- tc2[1]
    }
    
    plot_ly(comp_data) %>%
      add_trace(
        x = ~Team1,
        y = ~Metric,
        type = "bar",
        orientation = "h",
        name = input$team1,
        marker = list(color = team1_color)
      ) %>%
      add_trace(
        x = ~Team2,
        y = ~Metric,
        type = "bar",
        orientation = "h",
        name = input$team2,
        marker = list(color = team2_color)
      ) %>%
      layout(
        title = paste(input$team1, "vs", input$team2),
        xaxis = list(title = "EPA per Play"),
        yaxis = list(title = ""),
        barmode = "group",
        showlegend = TRUE
      )
  })
  
  # ===== TEAM STATS TABLE =====
  
  output$team_stats_table <- renderDT({
    data <- nfl_data()
    
    req(input$team1, input$team2)
    
    if (is.null(data$offense)) {
      return(datatable(data.frame(Message = "No data available")))
    }
    
    team1_off <- data$offense %>% filter(offense_team == input$team1)
    team2_off <- data$offense %>% filter(offense_team == input$team2)
    
    if (nrow(team1_off) == 0 || nrow(team2_off) == 0) {
      return(datatable(data.frame(Message = "Team data not available")))
    }
    
    stats <- bind_rows(
      team1_off %>% mutate(Team = input$team1),
      team2_off %>% mutate(Team = input$team2)
    ) %>%
      select(
        Team,
        `EPA/Play` = avg_epa,
        `Pass EPA` = pass_epa,
        `Rush EPA` = rush_epa,
        `Success Rate` = success_rate,
        `Explosive %` = explosive_play_rate
      ) %>%
      mutate(
        `EPA/Play` = sprintf("%.3f", as.numeric(`EPA/Play`)),
        `Pass EPA` = sprintf("%.3f", as.numeric(`Pass EPA`)),
        `Rush EPA` = sprintf("%.3f", as.numeric(`Rush EPA`)),
        `Success Rate` = sprintf("%.1f%%", as.numeric(`Success Rate`) * 100),
        `Explosive %` = sprintf("%.1f%%", as.numeric(`Explosive %`) * 100)
      )
    
    datatable(
      stats,
      options = list(
        dom = 't',
        scrollX = TRUE
      ),
      rownames = FALSE,
      class = 'cell-border stripe'
    )
  })
}

# ============================================================================
# RUN APP
# ============================================================================

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║     NFL BETTING DASHBOARD V3 - STARTING                        ║\n")
cat("║     Now with CORRECT column names!                             ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n")
cat("\n")

shinyApp(ui = ui, server = server)