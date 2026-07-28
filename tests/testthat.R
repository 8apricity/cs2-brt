source(file.path("R", "functions.R"), local = FALSE)
testthat::test_dir(file.path("tests", "testthat"), reporter = "summary")
