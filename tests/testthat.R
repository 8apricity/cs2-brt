source(here::here("R", "functions.R"), local = FALSE)
testthat::test_dir(here::here("tests", "testthat"), reporter = "summary")
