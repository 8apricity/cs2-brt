if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv", repos = "https://cloud.r-project.org")
}

if (!file.exists("renv/activate.R")) {
  renv::init(bare = TRUE, restart = FALSE)
}

required_packages <- c(
  "targets",
  "tarchetypes",
  "testthat",
  "lintr",
  "styler",
  "quarto",
  "knitr"
)

renv::install(required_packages)
renv::snapshot(prompt = FALSE)

message("Setup complete. Run targets::tar_make() to build the analysis.")
