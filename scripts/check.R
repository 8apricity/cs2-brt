source(file.path("R", "functions.R"))

testthat::test_dir(
  file.path("tests", "testthat"),
  reporter = "summary",
  stop_on_failure = TRUE
)

lint_results <- c(
  lintr::lint_dir("R"),
  lintr::lint_dir("tests"),
  lintr::lint_dir("scripts"),
  lintr::lint("_targets.R")
)

if (length(lint_results) > 0L) {
  print(lint_results)
  stop("Lint issues found.", call. = FALSE)
}

targets::tar_validate(callr_function = NULL)
