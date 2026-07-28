testthat::test_that("clean_observations normalizes and removes incomplete rows", {
  input <- data.frame(
    group = c(" Control ", "TREATMENT", NA),
    value = c(10, 12, 14)
  )

  result <- clean_observations(input)

  testthat::expect_equal(result$group, c("control", "treatment"))
  testthat::expect_equal(result$value, c(10, 12))
})

testthat::test_that("clean_observations requires the expected columns", {
  testthat::expect_error(
    clean_observations(data.frame(group = "control")),
    "Missing required columns: value"
  )
})

testthat::test_that("summarise_observations calculates group summaries", {
  input <- data.frame(
    group = c("control", "control", "treatment", "treatment"),
    value = c(10, 12, 14, 16)
  )

  result <- summarise_observations(input)

  testthat::expect_equal(result$group, c("control", "treatment"))
  testthat::expect_equal(result$n, c(2L, 2L))
  testthat::expect_equal(result$mean, c(11, 15))
  testthat::expect_equal(result$sd, c(sqrt(2), sqrt(2)))
})
