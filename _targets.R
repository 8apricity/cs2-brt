here::i_am("_targets.R")

library(targets)

tar_option_set(
  packages = c("jsonlite", "readr", "sf", "xml2"),
  format = "rds",
  seed = 20260728
)

source(here::here("R", "functions.R"))

list(
  tar_target(
    land_price_config_files,
    c(
      here::here("config", "land_price_columns.csv"),
      here::here("config", "land_price_mappings.yml")
    ),
    format = "file"
  ),
  tar_target(
    land_price_publication_raw_files,
    list.files(
      here::here("data", "raw", "land_price_publication"),
      recursive = TRUE,
      full.names = TRUE
    ),
    format = "file"
  ),
  tar_target(
    prefectural_land_price_survey_raw_files,
    list.files(
      here::here("data", "raw", "prefectural_land_price_survey"),
      recursive = TRUE,
      full.names = TRUE
    ),
    format = "file"
  ),
  tar_target(
    land_price_publication_outputs,
    {
      land_price_config_files
      land_price_publication_raw_files
      process_land_price_dataset(
        raw_dir = here::here("data", "raw", "land_price_publication"),
        output_dir = here::here("data", "processed"),
        dataset = "land_price_publication"
      )
    },
    format = "file"
  ),
  tar_target(
    prefectural_land_price_survey_outputs,
    {
      land_price_config_files
      prefectural_land_price_survey_raw_files
      process_land_price_dataset(
        raw_dir = here::here(
          "data",
          "raw",
          "prefectural_land_price_survey"
        ),
        output_dir = here::here("data", "processed"),
        dataset = "prefectural_land_price_survey"
      )
    },
    format = "file"
  ),
  tar_target(
    brt_stop_history_file,
    here::here("data", "manual", "brt_stop_history.csv"),
    format = "file"
  ),
  tar_target(
    brt_stop_coordinate_validation_file,
    here::here(
      "data",
      "manual",
      "brt_stop_coordinate_validation.csv"
    ),
    format = "file"
  ),
  tar_target(
    brt_stop_2022_xml_file,
    here::here(
      "data",
      "raw",
      "bus_stops",
      "P11-22_08_GML",
      "P11-22_08_GML",
      "P11-22_08.xml"
    ),
    format = "file"
  ),
  tar_target(
    brt_stop_outputs,
    process_brt_stops(
      history_file = brt_stop_history_file,
      xml_file = brt_stop_2022_xml_file,
      validation_file = brt_stop_coordinate_validation_file,
      output_dir = here::here("data", "processed")
    ),
    format = "file"
  )
)
