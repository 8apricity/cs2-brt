here::i_am("_targets.R")

library(targets)
library(tarchetypes)

tar_option_set(
  packages = character(0),
  format = "rds",
  seed = 20260728
)

source(here::here("R", "functions.R"))

list(
  tar_target(
    raw_data_file,
    here::here("data", "raw", "example.csv"),
    format = "file"
  ),
  tar_target(
    raw_data,
    read.csv(raw_data_file, stringsAsFactors = FALSE)
  ),
  tar_target(
    analysis_data,
    clean_observations(raw_data)
  ),
  tar_target(
    summary_table,
    summarise_observations(analysis_data)
  ),
  tar_quarto(
    report,
    path = here::here("index.qmd")
  )
)
