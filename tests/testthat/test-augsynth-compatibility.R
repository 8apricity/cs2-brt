testthat::test_that("augsynth fits a single-treated-unit panel", {
  withr::local_seed(20260827)

  units <- rep(sprintf("u%02d", 1:8), each = 10)
  years <- rep(2001:2010, times = 8)
  treatment <- as.integer(units == "u01" & years >= 2007)
  outcome <-
    rep(seq(-0.7, 0.7, length.out = 8), each = 10) +
    0.15 * (years - 2001) +
    stats::rnorm(length(years), sd = 0.03) +
    0.4 * treatment

  panel <- data.frame(
    outcome = outcome,
    treatment = treatment,
    unit = units,
    year = years
  )

  fit <- augsynth::augsynth(
    outcome ~ treatment,
    unit = unit,
    time = year,
    data = panel,
    t_int = 2007,
    progfunc = "ridge",
    scm = TRUE,
    fixedeff = TRUE
  )

  testthat::expect_s3_class(fit, "augsynth")
  testthat::expect_equal(nrow(fit$weights), 7L)
  testthat::expect_identical(fit$trt_unit, "u01")
})
