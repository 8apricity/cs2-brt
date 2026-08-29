land_price_analysis_fixture <- function() {
  sf::st_as_sf(
    data.frame(
      observation_id = c("a-2010", "a-2011", "b-2010-1", "b-2010-2"),
      source_dataset = rep("land_price_publication", 4L),
      source_year = c(2010L, 2011L, 2010L, 2010L),
      reference_date = as.Date(c(
        "2010-01-01",
        "2011-01-01",
        "2010-01-01",
        "2010-01-01"
      )),
      price_yen_per_m2 = c(100, 110, 200, 220),
      area_m2 = c(120, 120, 80, 90),
      current_use_raw = c("住宅", "住宅", "店舗", "事務所"),
      x = c(0, 2, 100, 102),
      y = c(0, 0, 0, 0)
    ),
    coords = c("x", "y"),
    crs = 6677
  )
}

testthat::test_that("land-price analysis data has stable point IDs", {
  observations <- land_price_analysis_fixture()
  prepared <- prepare_land_price_analysis_data(
    observations,
    point_match_tolerance_m = 5,
    metric_crs = 6677
  )
  shuffled <- prepare_land_price_analysis_data(
    observations[c(4, 2, 1, 3), ],
    point_match_tolerance_m = 5,
    metric_crs = 6677
  )

  point_ids <- sf::st_drop_geometry(prepared$point_year_panel) |>
    dplyr::select("observation_id", "point_id") |>
    dplyr::arrange(.data$observation_id)
  shuffled_point_ids <- sf::st_drop_geometry(shuffled$point_year_panel) |>
    dplyr::select("observation_id", "point_id") |>
    dplyr::arrange(.data$observation_id)

  testthat::expect_equal(point_ids, shuffled_point_ids)
  testthat::expect_true(all(grepl(
    "^land_price_publication_[0-9]{5}$",
    point_ids$point_id
  )))
  testthat::expect_s3_class(prepared$point_year_panel, "sf")
  testthat::expect_equal(
    prepared$point_year_panel$area_m2,
    observations$area_m2
  )
  testthat::expect_equal(nrow(prepared$point_registry), 2L)
  testthat::expect_equal(prepared$quality$clustered_point_count, 2L)
  testthat::expect_equal(prepared$quality$duplicate_point_year_count, 1L)

  duplicate_rows <- prepared$point_year_panel |>
    sf::st_drop_geometry() |>
    dplyr::filter(.data$observation_id %in% c("b-2010-1", "b-2010-2"))
  testthat::expect_equal(duplicate_rows$point_year_observation_count, c(2L, 2L))
  testthat::expect_true(all(duplicate_rows$duplicate_point_year))

  duplicate_point <- prepared$point_registry |>
    sf::st_drop_geometry() |>
    dplyr::filter(.data$duplicate_point_year_count == 1L)
  testthat::expect_equal(duplicate_point$observation_count, 2L)
  testthat::expect_equal(duplicate_point$first_source_year, 2010L)
  testthat::expect_equal(duplicate_point$last_source_year, 2010L)
  testthat::expect_equal(duplicate_point$observed_year_count, 1L)
})

testthat::test_that("land-price analysis data rejects mixed sources", {
  observations <- land_price_analysis_fixture()
  observations$source_dataset[[4L]] <- "prefectural_land_price_survey"

  testthat::expect_error(
    prepare_land_price_analysis_data(
      observations,
      point_match_tolerance_m = 5,
      metric_crs = 6677
    ),
    "exactly one source dataset"
  )
})

testthat::test_that("point-stop distances contain every pair", {
  points <- sf::st_as_sf(
    data.frame(
      point_id = c("point_1", "point_2"),
      x = c(0, 100),
      y = c(0, 0)
    ),
    coords = c("x", "y"),
    crs = 6677
  )
  stops <- sf::st_as_sf(
    data.frame(
      stop_id = c("stop_1", "stop_2"),
      x = c(0, 300),
      y = c(0, 0)
    ),
    coords = c("x", "y"),
    crs = 6677
  )

  distances <- calculate_point_stop_distances(
    points,
    stops,
    metric_crs = 6677
  )

  testthat::expect_equal(
    names(distances),
    c("point_id", "stop_id", "distance_m")
  )
  testthat::expect_equal(nrow(distances), 4L)
  testthat::expect_equal(
    distances$distance_m,
    c(0, 300, 100, 200),
    tolerance = 1e-8
  )
})

testthat::test_that("complete point panels require one observation per requested year", {
  observations <- land_price_analysis_fixture()
  observations$source_year[[2L]] <- 2012L
  observations$reference_date[[2L]] <- as.Date("2012-01-01")
  prepared <- prepare_land_price_analysis_data(
    observations,
    point_match_tolerance_m = 5,
    metric_crs = 6677
  )

  complete <- filter_complete_point_panel(
    prepared$point_year_panel,
    years = c(2010L, 2012L)
  )

  testthat::expect_equal(nrow(complete), 2L)
  testthat::expect_equal(
    sort(complete$observation_id),
    c("a-2010", "a-2011")
  )
  testthat::expect_equal(sort(unique(complete$source_year)), c(2010L, 2012L))
})

testthat::test_that("BRT stop assignment uses opening date then distance", {
  point_stop_distances <- tidyr::expand_grid(
    point_id = c("point_1", "point_2", "point_3"),
    stop_id = c("early", "early_near", "late_near")
  ) |>
    dplyr::mutate(
      distance_m = c(
        100, 200, 50,
        100, 80, 50,
        300, 300, 300
      )
    )
  stops <- data.frame(
    stop_id = c("early", "early_near", "late_near"),
    start_date = as.Date(c("2013-03-25", "2013-03-25", "2015-03-25"))
  )

  assignment <- assign_brt_stop_radius(
    point_stop_distances,
    stops,
    stop_radius_m = 150,
    eligible_stop_ids = stops$stop_id
  )

  testthat::expect_equal(
    names(assignment),
    c(
      "point_id",
      "within_stop_radius",
      "stop_id",
      "opening_date",
      "distance_m"
    )
  )
  testthat::expect_equal(
    assignment$within_stop_radius,
    c(TRUE, TRUE, FALSE)
  )
  testthat::expect_equal(
    assignment$stop_id,
    c("early", "early_near", NA_character_)
  )
  testthat::expect_equal(
    assignment$opening_date,
    as.Date(c("2013-03-25", "2013-03-25", NA))
  )
  testthat::expect_equal(assignment$distance_m, c(100, 80, NA_real_))
})

testthat::test_that("BRT treatment panel follows active service periods", {
  point_year_panel <- tidyr::expand_grid(
    point_id = c("point_1", "point_2"),
    reference_date = as.Date(c(
      "2012-01-01",
      "2013-07-01",
      "2019-07-01",
      "2020-07-01"
    ))
  ) |>
    dplyr::mutate(source_year = as.integer(format(.data$reference_date, "%Y")))
  point_stop_distances <- tidyr::expand_grid(
    point_id = c("point_1", "point_2"),
    stop_id = c("phase1", "phase2")
  ) |>
    dplyr::mutate(distance_m = c(100, 200, 600, 300))
  stops <- data.frame(
    stop_id = c("phase1", "phase2"),
    start_date = as.Date(c("2013-03-25", "2018-03-26")),
    end_date = as.Date(c("2019-03-31", NA)),
    confidence = c("high", "medium"),
    historical_validation_status = c("user_verified", "provisional")
  )
  interruptions <- data.frame(
    stop_id = c("phase2", "phase2"),
    inactive_start_date = as.Date(c("2017-01-01", "2019-06-01")),
    inactive_end_date = as.Date(c("2017-01-31", "2019-08-31"))
  )

  treatment_panel <- derive_brt_treatment_panel(
    point_year_panel,
    point_stop_distances,
    stops,
    stop_radius_m = 250,
    service_interruptions = interruptions
  ) |>
    dplyr::arrange(.data$point_id, .data$reference_date)

  testthat::expect_equal(
    treatment_panel$within_active_stop_radius,
    c(FALSE, TRUE, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE)
  )
  testthat::expect_equal(
    treatment_panel$active_stop_count_within_radius,
    c(0L, 1L, 0L, 1L, 0L, 0L, 0L, 0L)
  )
  testthat::expect_equal(
    treatment_panel$nearest_active_stop_id,
    c(NA, "phase1", NA, "phase2", NA, "phase1", NA, "phase2")
  )
  testthat::expect_equal(
    treatment_panel$nearest_active_stop_distance_m,
    c(NA, 100, NA, 200, NA, 600, NA, 300)
  )
  testthat::expect_equal(
    treatment_panel$nearest_active_stop_confidence,
    c(NA, "high", NA, "medium", NA, "high", NA, "medium")
  )
  testthat::expect_equal(
    treatment_panel$stop_proximity_has_non_high_confidence,
    c(FALSE, FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE)
  )
  testthat::expect_equal(
    treatment_panel$stop_proximity_uses_unvalidated_historical_location,
    c(FALSE, FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE)
  )
})

testthat::test_that("BRT treatment panel separates event geography and timing", {
  point_year_panel <- tidyr::expand_grid(
    point_id = c("point_1", "point_2"),
    reference_date = as.Date(c(
      "2012-01-01",
      "2013-07-01",
      "2019-07-01",
      "2020-07-01"
    ))
  ) |>
    dplyr::mutate(source_year = as.integer(format(.data$reference_date, "%Y")))
  point_stop_distances <- tidyr::expand_grid(
    point_id = c("point_1", "point_2"),
    stop_id = c("phase1", "phase2")
  ) |>
    dplyr::mutate(distance_m = c(100, 200, 600, 300))
  stops <- data.frame(
    stop_id = c("phase1", "phase2"),
    start_date = as.Date(c("2013-03-25", "2018-03-26")),
    end_date = as.Date(c("2019-03-31", NA)),
    confidence = c("high", "medium"),
    historical_validation_status = c("user_verified", "provisional")
  )
  interruptions <- data.frame(
    stop_id = "phase2",
    inactive_start_date = as.Date("2019-06-01"),
    inactive_end_date = as.Date("2019-08-31")
  )
  service_events <- data.frame(
    event_id = c("2013", "2018", "2019_pause", "2019_resume"),
    event_date = as.Date(c(
      "2013-03-25",
      "2018-03-26",
      "2019-06-01",
      "2019-09-01"
    )),
    service_period = c(
      "phase1",
      "phase2_preview",
      "phase2_interrupted",
      "phase2_resumed"
    )
  )

  treatment_panel <- derive_brt_treatment_panel(
    point_year_panel,
    point_stop_distances,
    stops,
    stop_radius_m = 250,
    service_interruptions = interruptions,
    service_events = service_events
  ) |>
    dplyr::arrange(.data$point_id, .data$reference_date)

  testthat::expect_equal(
    treatment_panel$service_period,
    rep(c(
      "pre_brt",
      "phase1",
      "phase2_interrupted",
      "phase2_resumed"
    ), 2L)
  )
  testthat::expect_equal(
    treatment_panel$active_stop_proximity_gain_2013,
    c(rep(TRUE, 4L), rep(FALSE, 4L))
  )
  testthat::expect_equal(
    treatment_panel$post_2013,
    rep(c(FALSE, TRUE, TRUE, TRUE), 2L)
  )
  testthat::expect_equal(
    treatment_panel$active_stop_proximity_gain_2013_treated,
    c(FALSE, TRUE, TRUE, TRUE, rep(FALSE, 4L))
  )
  testthat::expect_equal(
    treatment_panel$active_stop_proximity_loss_2019_pause,
    c(rep(TRUE, 4L), rep(FALSE, 4L))
  )
  testthat::expect_equal(
    treatment_panel$active_stop_proximity_loss_2019_pause_treated,
    c(FALSE, FALSE, TRUE, TRUE, rep(FALSE, 4L))
  )
  testthat::expect_equal(
    treatment_panel$active_stop_proximity_gain_2019_resume_treated,
    c(FALSE, FALSE, FALSE, TRUE, rep(FALSE, 4L))
  )
})

testthat::test_that("BRT stop proximity reports treatment reversals", {
  panel_with_reversal <- data.frame(
    point_id = rep(c("point_1", "point_2"), each = 3L),
    reference_date = rep(
      as.Date(c("2018-01-01", "2019-01-01", "2020-01-01")),
      2L
    ),
    within_active_stop_radius = c(FALSE, TRUE, FALSE, FALSE, TRUE, TRUE)
  )

  testthat::expect_error(
    assert_brt_proximity_monotone(
      panel_with_reversal,
      source_label = "publication"
    ),
    "publication.*1 treatment reversal.*point_1.*2020-01-01"
  )

  monotone_panel <- dplyr::filter(
    panel_with_reversal,
    .data$point_id == "point_2"
  )
  testthat::expect_identical(
    assert_brt_proximity_monotone(monotone_panel),
    monotone_panel
  )
})

testthat::test_that("baseline covariates use an exact observed year", {
  observations <- land_price_analysis_fixture()
  observations$area_m2[[2L]] <- NA_real_
  prepared <- prepare_land_price_analysis_data(
    observations,
    point_match_tolerance_m = 5,
    metric_crs = 6677
  )

  baseline <- build_baseline_covariates(
    prepared$point_year_panel,
    baseline_year = 2011L,
    columns = c("area_m2", "current_use_raw")
  )

  expected_point_id <- prepared$point_year_panel |>
    sf::st_drop_geometry() |>
    dplyr::filter(.data$observation_id == "a-2011") |>
    dplyr::pull(.data$point_id)
  testthat::expect_equal(
    names(baseline),
    c("point_id", "baseline_source_year", "area_m2", "current_use_raw")
  )
  testthat::expect_equal(nrow(baseline), 1L)
  testthat::expect_equal(baseline$point_id, expected_point_id)
  testthat::expect_equal(baseline$baseline_source_year, 2011L)
  testthat::expect_true(is.na(baseline$area_m2))
  testthat::expect_equal(baseline$current_use_raw, "住宅")
})

testthat::test_that("baseline covariates reject multiple observations per point", {
  prepared <- prepare_land_price_analysis_data(
    land_price_analysis_fixture(),
    point_match_tolerance_m = 5,
    metric_crs = 6677
  )

  testthat::expect_error(
    build_baseline_covariates(
      prepared$point_year_panel,
      baseline_year = 2010L,
      columns = "area_m2"
    ),
    "multiple observations"
  )
})

testthat::test_that("baseline covariates reject identifier and time columns", {
  prepared <- prepare_land_price_analysis_data(
    land_price_analysis_fixture(),
    point_match_tolerance_m = 5,
    metric_crs = 6677
  )

  testthat::expect_error(
    build_baseline_covariates(
      prepared$point_year_panel,
      baseline_year = 2011L,
      columns = c("observation_id", "reference_date")
    ),
    "cannot be used as baseline covariates"
  )
})

testthat::test_that("baseline covariates reject geometry columns", {
  prepared <- prepare_land_price_analysis_data(
    land_price_analysis_fixture(),
    point_match_tolerance_m = 5,
    metric_crs = 6677
  )

  testthat::expect_error(
    build_baseline_covariates(
      prepared$point_year_panel,
      baseline_year = 2011L,
      columns = attr(prepared$point_year_panel, "sf_column")
    ),
    "geometry or list columns"
  )
})

testthat::test_that("baseline covariates reject list columns", {
  prepared <- prepare_land_price_analysis_data(
    land_price_analysis_fixture(),
    point_match_tolerance_m = 5,
    metric_crs = 6677
  )
  prepared$point_year_panel$list_covariate <- rep(
    list(c("first", "second")),
    nrow(prepared$point_year_panel)
  )

  testthat::expect_error(
    build_baseline_covariates(
      prepared$point_year_panel,
      baseline_year = 2011L,
      columns = "list_covariate"
    ),
    "geometry or list columns"
  )
})
