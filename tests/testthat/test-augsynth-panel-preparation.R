testthat::test_that("land prices become simultaneous and staggered panels", {
  years <- 2012:2016
  point_x <- rep(c(0, 1000, 3000), each = length(years))
  point_y <- rep(c(0, 0, 0), each = length(years))
  jitter <- rep(c(-1, 0, 1, 0, -1), times = 3)
  observations <- sf::st_as_sf(
    data.frame(
      source_year = rep(years, times = 3),
      reference_date = as.Date(sprintf(
        "%04d-01-01",
        rep(years, times = 3)
      )),
      price_yen_per_m2 = rep(c(100, 120, 80), each = length(years)) +
        rep(seq_along(years), times = 3),
      x = point_x + jitter,
      y = point_y
    ),
    coords = c("x", "y"),
    crs = 6677
  )
  stops <- sf::st_as_sf(
    data.frame(
      stop_id = c("P1", "P2"),
      start_date = as.Date(c("2013-03-25", "2015-03-25")),
      phase = c("phase1", "phase2_preview"),
      phase1_initial = c(TRUE, FALSE),
      x = c(0, 1000),
      y = c(0, 0)
    ),
    coords = c("x", "y"),
    crs = 6677
  )

  prepared <- prepare_augsynth_panels(
    observations,
    stops,
    phase1_years = years,
    staggered_years = years,
    point_match_tolerance_m = 5,
    treatment_radius_m = 200,
    metric_crs = 6677,
    unit_prefix = "fixture"
  )

  testthat::expect_equal(prepared$quality$clustered_point_count, 3L)
  testthat::expect_equal(prepared$quality$phase1_unit_count, 3L)
  testthat::expect_equal(prepared$quality$phase1_treated_unit_count, 1L)
  testthat::expect_equal(prepared$quality$staggered_treated_unit_count, 2L)
  testthat::expect_equal(prepared$quality$staggered_cohort_count, 2L)
  testthat::expect_equal(prepared$quality$staggered_control_unit_count, 1L)
  testthat::expect_equal(nrow(prepared$phase1), 15L)
  testthat::expect_equal(nrow(prepared$staggered), 15L)
  testthat::expect_equal(
    anyDuplicated(prepared$staggered[c("unit_id", "year")]),
    0L
  )

  phase1_point <- prepared$staggered |>
    dplyr::filter(.data$first_brt_stop_id == "P1")
  phase2_point <- prepared$staggered |>
    dplyr::filter(.data$first_brt_stop_id == "P2")
  control_point <- prepared$staggered |>
    dplyr::filter(!.data$ever_brt_exposed)

  testthat::expect_equal(unique(phase1_point$phase1_treatment_year), 2014L)
  testthat::expect_equal(
    unique(phase1_point$first_brt_treatment_year),
    2014L
  )
  testthat::expect_equal(
    unique(phase2_point$first_brt_treatment_year),
    2016L
  )
  testthat::expect_equal(
    phase1_point$staggered_treated,
    as.integer(years >= 2014L)
  )
  testthat::expect_equal(
    phase2_point$staggered_treated,
    as.integer(years >= 2016L)
  )
  testthat::expect_true(all(control_point$staggered_treated == 0L))
})

testthat::test_that("treatment year respects each source reference date", {
  opening <- as.Date(c("2013-03-25", "2013-08-01", NA))

  testthat::expect_equal(
    first_observed_treatment_year(opening, 1L, 1L),
    c(2014L, 2014L, NA_integer_)
  )
  testthat::expect_equal(
    first_observed_treatment_year(opening, 7L, 1L),
    c(2013L, 2014L, NA_integer_)
  )
})
