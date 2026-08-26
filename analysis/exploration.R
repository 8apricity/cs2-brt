source(here::here("R", "functions.R"))

# Exploratory settings. Changing these values creates sensitivity specifications;
# it does not change the research-wide definition of the treated area.
point_match_tolerance_m <- 10
treatment_radius_m <- 1500
metric_crs <- 6677
phase1_years <- 2000:2017
staggered_years <- 2000:2025
multisynth_n_lags <- 8L
multisynth_n_leads <- 7L

stops <- sf::st_read(
  here::here("data", "processed", "brt_stops.gpkg"),
  quiet = TRUE
)
land_price_publication <- sf::st_read(
  here::here(
    "data",
    "processed",
    "land_price_publication.gpkg"
  ),
  layer = "observations",
  quiet = TRUE
)
prefectural_land_price_survey <- sf::st_read(
  here::here(
    "data",
    "processed",
    "prefectural_land_price_survey.gpkg"
  ),
  layer = "observations",
  quiet = TRUE
)

land_price_publication_augsynth_data <-
  prepare_augsynth_panels(
    land_price_publication,
    stops,
    phase1_years = phase1_years,
    staggered_years = staggered_years,
    point_match_tolerance_m = point_match_tolerance_m,
    treatment_radius_m = treatment_radius_m,
    metric_crs = metric_crs,
    unit_prefix = "publication"
  )
prefectural_land_price_survey_augsynth_data <-
  prepare_augsynth_panels(
    prefectural_land_price_survey,
    stops,
    phase1_years = phase1_years,
    staggered_years = staggered_years,
    point_match_tolerance_m = point_match_tolerance_m,
    treatment_radius_m = treatment_radius_m,
    metric_crs = metric_crs,
    unit_prefix = "prefectural_survey"
  )

# These four data frames are balanced long panels ready for direct reuse.
land_price_publication_phase1_panel <-
  land_price_publication_augsynth_data$phase1
land_price_publication_staggered_panel <-
  land_price_publication_augsynth_data$staggered
prefectural_land_price_survey_phase1_panel <-
  prefectural_land_price_survey_augsynth_data$phase1
prefectural_land_price_survey_staggered_panel <-
  prefectural_land_price_survey_augsynth_data$staggered

augsynth_panel_quality <- dplyr::bind_rows(
  land_price_publication_augsynth_data$quality |>
    dplyr::mutate(source = "land_price_publication", .before = 1L),
  prefectural_land_price_survey_augsynth_data$quality |>
    dplyr::mutate(
      source = "prefectural_land_price_survey",
      .before = 1L
    )
)

publication_phase1_t_int <- min(
  land_price_publication_phase1_panel$phase1_treatment_year,
  na.rm = TRUE
)
survey_phase1_t_int <- min(
  prefectural_land_price_survey_phase1_panel$phase1_treatment_year,
  na.rm = TRUE
)

# Simultaneous-adoption specification for the initial Phase I stops.
land_price_publication_augsynth_fit <- augsynth::augsynth(
  log_price ~ phase1_treated,
  unit = unit_id,
  time = year,
  t_int = publication_phase1_t_int,
  data = land_price_publication_phase1_panel,
  progfunc = "ridge",
  scm = TRUE,
  fixedeff = TRUE
)
prefectural_land_price_survey_augsynth_fit <- augsynth::augsynth(
  log_price ~ phase1_treated,
  unit = unit_id,
  time = year,
  t_int = survey_phase1_t_int,
  data = prefectural_land_price_survey_phase1_panel,
  progfunc = "ridge",
  scm = TRUE,
  fixedeff = TRUE
)

# Staggered-adoption specification. A point enters treatment after the first
# BRT stop within treatment_radius_m has opened and the source is next observed.
land_price_publication_multisynth_fit <- augsynth::multisynth(
  log_price ~ staggered_treated,
  unit = unit_id,
  time = year,
  data = land_price_publication_staggered_panel,
  n_lags = multisynth_n_lags,
  n_leads = multisynth_n_leads,
  scm = TRUE,
  fixedeff = TRUE
)
prefectural_land_price_survey_multisynth_fit <- augsynth::multisynth(
  log_price ~ staggered_treated,
  unit = unit_id,
  time = year,
  data = prefectural_land_price_survey_staggered_panel,
  n_lags = multisynth_n_lags,
  n_leads = multisynth_n_leads,
  scm = TRUE,
  fixedeff = TRUE
)
