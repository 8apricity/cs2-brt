if (!file.exists("renv.lock")) {
  stop("renv.lock not found.", call. = FALSE)
}

if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv", repos = "https://cloud.r-project.org")
}

if (!file.exists("renv/activate.R")) {
  renv::activate()
}

renv::restore(prompt = FALSE)

message("Setup complete. Run targets::tar_make() to build the analysis.")
