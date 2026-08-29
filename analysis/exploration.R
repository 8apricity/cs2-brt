source(here::here("R", "functions.R"))

# Exploratory settings. They do not define the study-wide treated area,
# analysis period, or adopted covariate specification.
point_match_tolerance_m <- 10
treatment_radius_m <- 1500
metric_crs <- 6677
example_panel_years <- 2000:2017
baseline_year <- 2010L
baseline_covariate_columns <- character()
# Candidate core columns include area_m2, current_use_raw,
# transport_distance_m, building_coverage_pct, and floor_area_ratio_pct.
# Check their meaning, availability, and pre-treatment timing before use.

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

land_price_sources <- list(
  publication = land_price_publication,
  survey = prefectural_land_price_survey
)
land_price_analysis <- purrr::map(
  land_price_sources,
  prepare_land_price_analysis_data,
  point_match_tolerance_m = point_match_tolerance_m,
  metric_crs = metric_crs
)
point_stop_distances <- purrr::map(
  land_price_analysis,
  function(analysis_data) {
    calculate_point_stop_distances(
      analysis_data$point_registry,
      stops,
      metric_crs = metric_crs
    )
  }
)

phase1_stop_ids <- stops |>
  sf::st_drop_geometry() |>
  dplyr::filter(.data$phase1_initial) |>
  dplyr::pull(.data$stop_id)

phase1_exposure <- purrr::map(
  point_stop_distances,
  derive_brt_exposure,
  stops = stops,
  treatment_radius_m = treatment_radius_m,
  eligible_stop_ids = phase1_stop_ids
)

# Example of constructing a complete panel and a date-based treatment column.
# The base analysis data remain unbalanced and contain no treatment column.
example_panels <- purrr::map2(
  land_price_analysis,
  phase1_exposure,
  function(analysis_data, exposure) {
    filter_complete_point_panel(
      analysis_data$point_year_panel,
      years = example_panel_years
    ) |>
      dplyr::left_join(
        exposure |>
          dplyr::rename(
            phase1_exposed = "exposed",
            phase1_stop_id = "stop_id",
            phase1_opening_date = "opening_date",
            phase1_distance_m = "distance_m"
          ),
        by = "point_id"
      ) |>
      dplyr::mutate(
        phase1_treated = as.integer(
          .data$phase1_exposed &
            .data$reference_date >= .data$phase1_opening_date
        ),
        log_price = log(.data$price_yen_per_m2)
      )
  }
)
baseline_covariates <- purrr::map(
  land_price_analysis,
  function(analysis_data) {
    build_baseline_covariates(
      analysis_data$point_year_panel,
      baseline_year = baseline_year,
      columns = baseline_covariate_columns
    )
  }
)

publication_fit <- augsynth::multisynth(
  log_price ~ phase1_treated,
  unit = point_id,
  time = source_year,
  data = sf::st_drop_geometry(example_panels$publication),
  fixedeff = FALSE,
  scm = TRUE,
)

publication_summary <- summary(publication_fit, inf_type = "jackknife")
publication_summary
plot(publication_summary)

