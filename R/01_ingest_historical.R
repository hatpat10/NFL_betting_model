suppressPackageStartupMessages({
  library(nflreadr)
  library(dplyr)
  library(arrow)
  library(DBI)
  library(RSQLite)
  library(janitor)
  library(purrr)
})

dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
dir.create("db", showWarnings = FALSE)

con <- dbConnect(RSQLite::SQLite(), "db/nfl.sqlite")

seasons <- 2010:2025

message("Loading schedules...")
schedules <- purrr::map_dfr(seasons, ~nflreadr::load_schedules(.x)) %>%
  janitor::clean_names()

message("Saving schedules parquet...")
arrow::write_parquet(schedules, "data/raw/schedules.parquet")

DBI::dbWriteTable(con, "schedules", schedules, overwrite = TRUE)

message("Loading play-by-play (this may take a while)...")
pbp <- purrr::map_dfr(seasons, ~nflreadr::load_pbp(.x)) %>%
  janitor::clean_names()

message("Saving pbp parquet...")
arrow::write_parquet(pbp, "data/raw/pbp.parquet")

DBI::dbDisconnect(con)
message("Done: data/raw/schedules.parquet and data/raw/pbp.parquet created.")
