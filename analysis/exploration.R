source(here::here("R", "functions.R"))

# Exploratory settings. They do not define the study-wide treated area,
# analysis period, or adopted covariate specification.
point_match_tolerance_m <- 10
treatment_radius_m <- 1500
metric_crs <- 6677
example_panel_years <- 2000:2025
baseline_year <- 2010L
baseline_covariate_columns <- character()
# Candidate core columns include area_m2, current_use_raw,
# transport_distance_m, building_coverage_pct, and floor_area_ratio_pct.
# Check their meaning, availability, and pre-treatment timing before use.

stops <- sf::st_read(
  here::here("data", "processed", "brt_stops.gpkg"),
  quiet = TRUE
)
service_interruptions <- readr::read_csv(
  here::here("data", "manual", "brt_stop_service_interruptions.csv"),
  col_types = readr::cols(
    stop_id = readr::col_character(),
    inactive_start_date = readr::col_date(),
    inactive_end_date = readr::col_date(),
    .default = readr::col_character()
  )
)
access_events <- tibble::tribble(
  ~event_id, ~event_date, ~service_period,
  "2013", as.Date("2013-03-25"), "phase1_2013",
  "2016", as.Date("2016-02-01"), "phase1_added_2016",
  "2018", as.Date("2018-03-26"), "phase2_preview_2018",
  "2019", as.Date("2019-04-01"), "phase2_full_2019",
  "2021_pause", as.Date("2021-02-01"), "phase2_sunpia_paused_2021",
  "2022_resume", as.Date("2022-05-01"), "phase2_sunpia_resumed_2022"
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
treatment_panels <- purrr::map2(
  land_price_analysis,
  point_stop_distances,
  function(analysis_data, distances) {
    derive_brt_treatment_panel(
      analysis_data$point_year_panel,
      distances,
      stops,
      treatment_radius_m = treatment_radius_m,
      service_interruptions = service_interruptions,
      access_events = access_events
    )
  }
)

# Example of constructing a complete panel and a date-based treatment column.
# The standardized data remain unchanged; treatment_panels are unbalanced,
# in-memory analysis copies from which complete model panels are derived.
example_panels <- purrr::map2(
  treatment_panels,
  phase1_exposure,
  function(treatment_panel, exposure) {
    filter_complete_point_panel(
      treatment_panel,
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

active_access_model_panels <- purrr::imap(
  example_panels,
  function(panel, source_name) {
    assert_brt_access_is_monotone(
      panel,
      source_label = source_name
    ) |>
      sf::st_drop_geometry() |>
      dplyr::mutate(
        brt_access_active = as.integer(.data$brt_access_active)
      )
  }
)
active_access_diagnostics <- purrr::imap_dfr(
  active_access_model_panels,
  function(panel, source_name) {
    panel |>
      dplyr::group_by(.data$point_id) |>
      dplyr::summarise(
        access_reference_date = if (any(.data$brt_access_active == 1L)) {
          min(.data$reference_date[.data$brt_access_active == 1L])
        } else {
          as.Date(NA)
        },
        .groups = "drop"
      ) |>
      dplyr::count(
        .data$access_reference_date,
        name = "point_count",
        .drop = FALSE
      ) |>
      dplyr::mutate(source = source_name, .before = 1L)
  }
)
active_access_diagnostics
active_access_fits <- purrr::map(
  active_access_model_panels,
  function(panel) {
    augsynth::multisynth(
      log_price ~ brt_access_active,
      unit = point_id,
      time = source_year,
      data = panel,
      fixedeff = FALSE,
      scm = TRUE
    )
  }
)
active_access_summaries <- purrr::map(
  active_access_fits,
  summary,
  inf_type = "jackknife"
)
active_access_summaries
purrr::walk(active_access_summaries, plot)
