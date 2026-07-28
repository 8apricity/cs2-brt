#' Clean the example observations
#'
#' @param data A data frame with `group` and `value` columns.
#' @return A data frame containing complete, normalized observations.
clean_observations <- function(data) {
  required_columns <- c("group", "value")
  missing_columns <- setdiff(required_columns, names(data))

  if (length(missing_columns) > 0L) {
    stop(
      "Missing required columns: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }

  cleaned <- data[stats::complete.cases(data[required_columns]), required_columns]
  cleaned$group <- trimws(tolower(as.character(cleaned$group)))
  cleaned$value <- as.numeric(cleaned$value)
  rownames(cleaned) <- NULL
  cleaned
}

#' Summarise observations by group
#'
#' @param data A cleaned data frame with `group` and numeric `value` columns.
#' @return A data frame with sample size, mean, and standard deviation per group.
summarise_observations <- function(data) {
  if (!is.numeric(data$value)) {
    stop("`value` must be numeric.", call. = FALSE)
  }

  values_by_group <- split(data$value, data$group)

  data.frame(
    group = names(values_by_group),
    n = vapply(values_by_group, length, integer(1)),
    mean = vapply(values_by_group, mean, numeric(1)),
    sd = vapply(values_by_group, stats::sd, numeric(1)),
    row.names = NULL,
    check.names = FALSE
  )
}
