source(here::here("R", "functions.R"))

# The Phase I periods below follow decision 0007. The stop radius and
# covariate specification remain exploratory rather than adopted settings.
point_match_tolerance_m <- 10
stop_radius_m <- 1500
metric_crs <- 6677
phase1_primary_panel_years <- 2000:2015
phase1_supplementary_panel_years <- 2000:2017
phase1_sensitivity_panel_years_by_specification <- list(
  start_2005 = 2005:2015,
  start_2009 = 2009:2015
)
active_stop_proximity_panel_years <- 2000:2025
baseline_year <- 2010L
baseline_covariate_columns <- character()
# Candidate core columns include area_m2, current_use_raw,
# transport_distance_m, building_coverage_pct, and floor_area_ratio_pct.
# Check their meaning, availability, and pre-treatment timing before use.

brt_stops <- sf::st_read(
  here::here("data", "processed", "brt_stops.gpkg"),
  quiet = TRUE
)
brt_stop_service_interruptions <- readr::read_csv(
  here::here("data", "manual", "brt_stop_service_interruptions.csv"),
  col_types = readr::cols(
    stop_id = readr::col_character(),
    inactive_start_date = readr::col_date(),
    inactive_end_date = readr::col_date(),
    .default = readr::col_character()
  )
)
brt_service_events <- tibble::tribble(
  ~event_id, ~event_date, ~service_period,
  "2013", as.Date("2013-03-25"), "phase1_2013",
  "2016", as.Date("2016-02-01"), "phase1_added_2016",
  "2018", as.Date("2018-03-26"), "phase2_preview_2018",
  "2019", as.Date("2019-04-01"), "phase2_full_2019",
  "2021_pause", as.Date("2021-02-01"), "phase2_sunpia_paused_2021",
  "2022_resume", as.Date("2022-05-01"), "phase2_sunpia_resumed_2022"
)
land_price_publication <- sf::st_read(
  here::here(
    "data",
    "processed",
    "land_price_publication.gpkg"
  ),
  layer = "observations",
  quiet = TRUE
)
prefectural_land_price_survey <- sf::st_read(
  here::here(
    "data",
    "processed",
    "prefectural_land_price_survey.gpkg"
  ),
  layer = "observations",
  quiet = TRUE
)

land_price_observations_by_source <- list(
  land_price_publication = land_price_publication,
  prefectural_land_price_survey = prefectural_land_price_survey
)
analysis_data_by_source <- purrr::map(
  land_price_observations_by_source,
  prepare_land_price_analysis_data,
  point_match_tolerance_m = point_match_tolerance_m,
  metric_crs = metric_crs
)
point_stop_distances_by_source <- purrr::map(
  analysis_data_by_source,
  function(analysis_data) {
    calculate_point_stop_distances(
      analysis_data$point_registry,
      brt_stops,
      metric_crs = metric_crs
    )
  }
)

phase1_stop_ids <- brt_stops |>
  sf::st_drop_geometry() |>
  dplyr::filter(.data$phase1_initial) |>
  dplyr::pull(.data$stop_id)

phase1_stop_assignments_by_source <- purrr::map(
  point_stop_distances_by_source,
  assign_brt_stop_within_radius,
  stops = brt_stops,
  stop_radius_m = stop_radius_m,
  eligible_stop_ids = phase1_stop_ids
)
treatment_panels_by_source <- purrr::map2(
  analysis_data_by_source,
  point_stop_distances_by_source,
  function(analysis_data, distances) {
    derive_brt_treatment_panel(
      analysis_data$point_year_panel,
      distances,
      brt_stops,
      stop_radius_m = stop_radius_m,
      service_interruptions = brt_stop_service_interruptions,
      service_events = brt_service_events
    )
  }
)

# Build a complete panel directly for the requested years. In particular, the
# Phase I samples are not conditioned on a point remaining observed through
# 2025.
build_complete_model_panels_by_source <- function(panel_years) {
  purrr::map2(
    treatment_panels_by_source,
    phase1_stop_assignments_by_source,
    function(treatment_panel, stop_assignment) {
      filter_complete_point_panel(
        treatment_panel,
        years = panel_years
      ) |>
        dplyr::left_join(
          stop_assignment |>
            dplyr::rename(
              phase1_within_stop_radius = "within_stop_radius",
              phase1_stop_id = "stop_id",
              phase1_opening_date = "opening_date",
              phase1_distance_m = "distance_m"
            ),
          by = "point_id"
        ) |>
        dplyr::mutate(
          phase1_treated = as.integer(
            .data$phase1_within_stop_radius &
              .data$reference_date >= .data$phase1_opening_date
          ),
          log_price = log(.data$price_yen_per_m2)
        ) |>
        sf::st_drop_geometry()
    }
  )
}

phase1_model_panels_by_source <- build_complete_model_panels_by_source(
  phase1_primary_panel_years
)
phase1_supplementary_panels_by_source <- build_complete_model_panels_by_source(
  phase1_supplementary_panel_years
)
phase1_sensitivity_panels_by_specification <- purrr::map(
  phase1_sensitivity_panel_years_by_specification,
  build_complete_model_panels_by_source
)
active_stop_proximity_model_panels_by_source <-
  build_complete_model_panels_by_source(
    active_stop_proximity_panel_years
  )
baseline_covariates_by_source <- purrr::map(
  analysis_data_by_source,
  function(analysis_data) {
    build_baseline_covariates(
      analysis_data$point_year_panel,
      baseline_year = baseline_year,
      columns = baseline_covariate_columns
    )
  }
)

active_stop_proximity_model_panels_by_source <- purrr::imap(
  active_stop_proximity_model_panels_by_source,
  function(panel, source_name) {
    assert_brt_proximity_monotone(
      panel,
      source_label = source_name
    ) |>
      dplyr::mutate(
        within_active_stop_radius = as.integer(
          .data$within_active_stop_radius
        )
      )
  }
)
active_stop_proximity_diagnostics <- purrr::imap_dfr(
  active_stop_proximity_model_panels_by_source,
  function(panel, source_name) {
    panel |>
      dplyr::group_by(.data$point_id) |>
      dplyr::summarise(
        proximity_start_reference_date = if (
          any(.data$within_active_stop_radius == 1L)
        ) {
          min(
            .data$reference_date[.data$within_active_stop_radius == 1L]
          )
        } else {
          as.Date(NA)
        },
        .groups = "drop"
      ) |>
      dplyr::count(
        .data$proximity_start_reference_date,
        name = "point_count",
        .drop = FALSE
      ) |>
      dplyr::mutate(source = source_name, .before = 1L)
  }
)

summarise_phase1_samples <- function(panels_by_source, specification) {
  purrr::imap_dfr(
    panels_by_source,
    function(panel, source_name) {
      panel |>
        dplyr::group_by(.data$point_id) |>
        dplyr::summarise(
          ever_treated = any(.data$phase1_treated == 1L),
          .groups = "drop"
        ) |>
        dplyr::summarise(
          point_count = dplyr::n(),
          treated_point_count = sum(.data$ever_treated),
          .groups = "drop"
        ) |>
        dplyr::mutate(
          specification = specification,
          source = source_name,
          first_year = min(panel$source_year),
          last_year = max(panel$source_year),
          .before = 1L
        )
    }
  )
}

phase1_sample_diagnostics <- dplyr::bind_rows(
  summarise_phase1_samples(
    phase1_model_panels_by_source,
    "primary_2000_2015"
  ),
  summarise_phase1_samples(
    phase1_supplementary_panels_by_source,
    "supplementary_2000_2017"
  ),
  purrr::imap_dfr(
    phase1_sensitivity_panels_by_specification,
    \(panels_by_source, specification) {
      summarise_phase1_samples(panels_by_source, specification)
    }
  )
)

phase1_sample_diagnostics

fit_multisynth_panels <- function(panels_by_source, treatment_column) {
  model_formula <- stats::reformulate(
    treatment_column,
    response = "log_price"
  )

  purrr::map(
    panels_by_source,
    function(panel) {
      augsynth::multisynth(
        model_formula,
        unit = point_id,
        time = source_year,
        data = panel,
        fixedeff = TRUE,
        scm = TRUE
      )
    }
  )
}

summarise_multisynth_panels <- function(fits_by_source) {
  purrr::map(
    fits_by_source,
    summary,
    inf_type = "jackknife"
  )
}

land_price_source_plot_titles <- c(
  land_price_publication = "Land Price Publication",
  prefectural_land_price_survey = "Prefectural Land Price Survey"
)

print_multisynth_summary_plots <- function(
  summaries_by_source,
  specification_title
) {
  purrr::iwalk(
    summaries_by_source,
    function(summary_object, source_name) {
      plot_title <- paste(
        specification_title,
        land_price_source_plot_titles[[source_name]],
        sep = " — "
      )

      print(
        plot(summary_object) +
          ggplot2::labs(title = plot_title)
      )
    }
  )
}

phase1_fits_by_source <- fit_multisynth_panels(
  phase1_model_panels_by_source,
  "phase1_treated"
)
phase1_summaries_by_source <- summarise_multisynth_panels(
  phase1_fits_by_source
)
phase1_summaries_by_source
print_multisynth_summary_plots(
  phase1_summaries_by_source,
  "Phase I primary (2000–2015)"
)

phase1_supplementary_fits_by_source <- fit_multisynth_panels(
  phase1_supplementary_panels_by_source,
  "phase1_treated"
)
phase1_supplementary_summaries_by_source <- summarise_multisynth_panels(
  phase1_supplementary_fits_by_source
)
phase1_supplementary_summaries_by_source
print_multisynth_summary_plots(
  phase1_supplementary_summaries_by_source,
  "Phase I supplementary (2000–2017)"
)

phase1_sensitivity_fits_by_specification <- purrr::map(
  phase1_sensitivity_panels_by_specification,
  fit_multisynth_panels,
  treatment_column = "phase1_treated"
)
phase1_sensitivity_summaries_by_specification <- purrr::map(
  phase1_sensitivity_fits_by_specification,
  summarise_multisynth_panels
)
phase1_sensitivity_summaries_by_specification
phase1_sensitivity_plot_titles <- c(
  start_2005 = "Phase I sensitivity (2005–2015)",
  start_2009 = "Phase I sensitivity (2009–2015)"
)
purrr::iwalk(
  phase1_sensitivity_summaries_by_specification,
  \(summaries_by_source, specification) {
    print_multisynth_summary_plots(
      summaries_by_source,
      phase1_sensitivity_plot_titles[[specification]]
    )
  }
)

active_stop_proximity_diagnostics

active_stop_proximity_fits_by_source <- fit_multisynth_panels(
  active_stop_proximity_model_panels_by_source,
  "within_active_stop_radius"
)

active_stop_proximity_summaries_by_source <- summarise_multisynth_panels(
  active_stop_proximity_fits_by_source
)
active_stop_proximity_summaries_by_source
print_multisynth_summary_plots(
  active_stop_proximity_summaries_by_source,
  "Active-stop proximity (2000–2025)"
)

# a <- active_stop_proximity_model_panels_by_source$prefectural_land_price_survey |>
#   dplyr::filter(within_active_stop_radius == 1) |>
#   dplyr::group_by(point_id) |>
#   dplyr::slice_min(source_year, n = 1, with_ties = FALSE) |>
#   dplyr::ungroup()
# 
# active_stop_proximity_summaries_by_source$prefectural_land_price_survey$att |>
#   dplyr::filter(Time == 6 & Level != "Average") |> 
#   dplyr::left_join(
#     a,
#     by = dplyr::join_by(Level == point_id)
#   ) |>
#   ggplot2::ggplot(ggplot2::aes(nearest_active_stop_distance_m, Estimate)) +
#     ggplot2::geom_point()

# -------------------------------------------------------------------------
# Leave-one-treated-unit-out (LOO) sensitivity analysis
# -------------------------------------------------------------------------

# Extract the overall average ATT from a summary.multisynth object.
# In summary.multisynth$att, Time = NA and Level = "Average"
# identifies the post-treatment average ATT.
extract_multisynth_average_att <- function(summary_object) {
  
  average_row <- summary_object$att |>
    dplyr::filter(
      is.na(.data$Time),
      .data$Level == "Average"
    )
  
  if (nrow(average_row) != 1L) {
    stop(
      "Could not uniquely identify the overall Average ATT row ",
      "from summary_object$att."
    )
  }
  
  average_row |>
    dplyr::transmute(
      att = .data$Estimate,
      std_error = .data$Std.Error,
      lower_bound = .data$lower_bound,
      upper_bound = .data$upper_bound
    )
}

summarise_average_atts <- function(summaries_by_source, specification) {
  purrr::imap_dfr(
    summaries_by_source,
    function(summary_object, source_name) {
      extract_multisynth_average_att(summary_object) |>
        dplyr::mutate(
          specification = specification,
          source = source_name,
          .before = 1L
        )
    }
  )
}

phase1_average_att_comparison <- dplyr::bind_rows(
  summarise_average_atts(
    phase1_summaries_by_source,
    "primary_2000_2015"
  ),
  summarise_average_atts(
    phase1_supplementary_summaries_by_source,
    "supplementary_2000_2017"
  ),
  purrr::imap_dfr(
    phase1_sensitivity_summaries_by_specification,
    \(summaries_by_source, specification) {
      summarise_average_atts(summaries_by_source, specification)
    }
  )
)

phase1_average_att_comparison


# Re-estimate multisynth after removing each treated point in turn.
run_multisynth_loo <- function(
  panel,
  source_name,
  reference_summary,
  treatment_column
) {
  
  # Identify points that are treated at least once in this analysis panel.
  treated_point_ids <- panel |>
    dplyr::group_by(.data$point_id) |>
    dplyr::summarise(
      ever_treated = any(
        .data[[treatment_column]] == 1L,
        na.rm = TRUE
      ),
      .groups = "drop"
    ) |>
    dplyr::filter(.data$ever_treated) |>
    dplyr::pull(.data$point_id)
  
  if (length(treated_point_ids) < 2L) {
    warning(
      source_name,
      ": fewer than two treated points were found; ",
      "LOO estimation may not be informative."
    )
  }
  
  # ATT from the original full-sample specification.
  reference_att <- extract_multisynth_average_att(
    reference_summary
  ) |>
    dplyr::pull(.data$att)
  
  purrr::map_dfr(
    treated_point_ids,
    function(omitted_point_id) {
      
      loo_panel <- panel |>
        dplyr::filter(
          .data$point_id != omitted_point_id
        )
      
      # Do not allow one failed LOO fit to stop all remaining fits.
      tryCatch(
        {
          
          model_formula <- stats::reformulate(
            treatment_column,
            response = "log_price"
          )

          loo_fit <- augsynth::multisynth(
            model_formula,
            unit = point_id,
            time = source_year,
            data = loo_panel,
            fixedeff = TRUE,
            scm = TRUE
          )
          
          loo_summary <- summary(
            loo_fit,
            inf_type = "jackknife"
          )
          
          loo_average <- extract_multisynth_average_att(
            loo_summary
          )
          
          tibble::tibble(
            source = source_name,
            omitted_point_id = as.character(omitted_point_id),
            n_treated_full = length(treated_point_ids),
            n_treated_loo = length(treated_point_ids) - 1L,
            full_att = reference_att,
            loo_att = loo_average$att,
            loo_std_error = loo_average$std_error,
            loo_lower_bound = loo_average$lower_bound,
            loo_upper_bound = loo_average$upper_bound,
            delta_from_full = loo_average$att - reference_att,
            error = NA_character_
          )
          
        },
        error = function(e) {
          
          tibble::tibble(
            source = source_name,
            omitted_point_id = as.character(omitted_point_id),
            n_treated_full = length(treated_point_ids),
            n_treated_loo = length(treated_point_ids) - 1L,
            full_att = reference_att,
            loo_att = NA_real_,
            loo_std_error = NA_real_,
            loo_lower_bound = NA_real_,
            loo_upper_bound = NA_real_,
            delta_from_full = NA_real_,
            error = conditionMessage(e)
          )
        }
      )
    }
  )
}


# -------------------------------------------------------------------------
# 1. Phase 1 specification
# -------------------------------------------------------------------------

phase1_loo_results <- purrr::imap_dfr(
  phase1_model_panels_by_source,
  function(panel, source_name) {
    run_multisynth_loo(
      panel = panel,
      source_name = source_name,
      reference_summary = phase1_summaries_by_source[[source_name]],
      treatment_column = "phase1_treated"
    )
  }
)

phase1_loo_results


# -------------------------------------------------------------------------
# 2. Supplementary Phase 1 specification (through 2017)
# -------------------------------------------------------------------------

phase1_supplementary_loo_results <- purrr::imap_dfr(
  phase1_supplementary_panels_by_source,
  function(panel, source_name) {
    run_multisynth_loo(
      panel = panel,
      source_name = source_name,
      reference_summary = phase1_supplementary_summaries_by_source[[
        source_name
      ]],
      treatment_column = "phase1_treated"
    )
  }
)

phase1_supplementary_loo_results


# -------------------------------------------------------------------------
# 3. All active-stop-proximity events
# -------------------------------------------------------------------------

active_stop_proximity_loo_results <- purrr::imap_dfr(
  active_stop_proximity_model_panels_by_source,
  function(panel, source_name) {
    run_multisynth_loo(
      panel = panel,
      source_name = source_name,
      reference_summary = active_stop_proximity_summaries_by_source[[
        source_name
      ]],
      treatment_column = "within_active_stop_radius"
    )
  }
)

active_stop_proximity_loo_results


# -------------------------------------------------------------------------
# Combine all LOO results
# -------------------------------------------------------------------------

loo_results <- dplyr::bind_rows(
  phase1_loo_results |>
    dplyr::mutate(
      specification = "phase1_primary_2000_2015",
      .before = 1L
    ),
  phase1_supplementary_loo_results |>
    dplyr::mutate(
      specification = "phase1_supplementary_2000_2017",
      .before = 1L
    ),
  active_stop_proximity_loo_results |>
    dplyr::mutate(
      specification = "active_stop_proximity",
      .before = 1L
    )
)


# Rank omitted points by their influence on the estimated ATT.
loo_results_ranked <- loo_results |>
  dplyr::arrange(
    .data$specification,
    .data$source,
    dplyr::desc(abs(.data$delta_from_full))
  )

loo_results_ranked


# -------------------------------------------------------------------------
# Compact stability diagnostics
# -------------------------------------------------------------------------

loo_stability_summary <- loo_results |>
  dplyr::group_by(
    .data$specification,
    .data$source
  ) |>
  dplyr::summarise(
    full_att = dplyr::first(.data$full_att),
    
    min_loo_att = if (all(is.na(.data$loo_att))) {
      NA_real_
    } else {
      min(.data$loo_att, na.rm = TRUE)
    },
    
    max_loo_att = if (all(is.na(.data$loo_att))) {
      NA_real_
    } else {
      max(.data$loo_att, na.rm = TRUE)
    },
    
    max_abs_change = if (all(is.na(.data$delta_from_full))) {
      NA_real_
    } else {
      max(
        abs(.data$delta_from_full),
        na.rm = TRUE
      )
    },
    
    sign_flip_count = sum(
      sign(.data$loo_att) != sign(.data$full_att),
      na.rm = TRUE
    ),
    
    failed_fits = sum(!is.na(.data$error)),
    .groups = "drop"
  )

loo_stability_summary


# -------------------------------------------------------------------------
# Plot: ATT after omitting each treated point
# Dashed horizontal line = full-sample ATT
# -------------------------------------------------------------------------

loo_plot <- loo_results |>
  dplyr::filter(is.na(.data$error)) |>
  ggplot2::ggplot(
    ggplot2::aes(
      x = stats::reorder(
        .data$omitted_point_id,
        .data$loo_att
      ),
      y = .data$loo_att
    )
  ) +
  ggplot2::geom_hline(
    ggplot2::aes(
      yintercept = .data$full_att
    ),
    linetype = 2
  ) +
  ggplot2::geom_errorbar(
    ggplot2::aes(
      ymin = .data$loo_lower_bound,
      ymax = .data$loo_upper_bound
    ),
    width = 0
  ) +
  ggplot2::geom_point() +
  ggplot2::facet_grid(
    specification ~ source,
    scales = "free"
  ) +
  ggplot2::coord_flip() +
  ggplot2::labs(
    x = "Omitted treated point_id",
    y = "Average ATT",
    title = "Leave-one-treated-point-out sensitivity analysis",
    subtitle = "Dashed line denotes the corresponding full-sample ATT"
  ) +
  ggplot2::theme_bw()

print(loo_plot)


# -------------------------------------------------------------------------
# Treated-point ATT heterogeneity diagnostics
# -------------------------------------------------------------------------

# nolint start: object_length_linter, object_usage_linter

# Extract the post-treatment average ATT for each treated point. These rows
# are descriptive point estimates; the small number of treated points does
# not support interpreting the cross-point associations below as causal.
extract_multisynth_unit_average_att <- function(summary_object) {
  unit_rows <- summary_object$att |>
    dplyr::filter(
      is.na(.data$Time),
      .data$Level != "Average"
    )

  if (nrow(unit_rows) == 0L) {
    stop("No treated-point average ATT rows were found.")
  }

  unit_rows |>
    dplyr::transmute(
      point_id = .data$Level,
      unit_average_att = .data$Estimate,
      unit_att_std_error = .data$Std.Error,
      unit_att_lower_bound = .data$lower_bound,
      unit_att_upper_bound = .data$upper_bound
    )
}

# Summarise how closely each treated point tracked its synthetic comparison
# before treatment. A large value indicates that apparent post-treatment
# heterogeneity may partly reflect an unstable counterfactual.
summarise_multisynth_unit_pre_fit <- function(summary_object) {
  summary_object$att |>
    dplyr::filter(
      !is.na(.data$Time),
      .data$Time < 0,
      .data$Level != "Average"
    ) |>
    dplyr::group_by(point_id = .data$Level) |>
    dplyr::summarise(
      pre_treatment_fit_rmse = sqrt(mean(.data$Estimate^2)),
      pre_treatment_fit_max_abs = max(abs(.data$Estimate)),
      .groups = "drop"
    )
}

calculate_log_price_slope <- function(source_year, log_price) {
  complete <- !is.na(source_year) & !is.na(log_price)
  source_year <- source_year[complete]
  log_price <- log_price[complete]

  if (length(source_year) < 2L || dplyr::n_distinct(source_year) < 2L) {
    return(NA_real_)
  }

  unname(stats::coef(stats::lm(log_price ~ source_year))[[2L]])
}

build_multisynth_unit_heterogeneity <- function(
  panel,
  summary_object,
  treatment_column,
  specification,
  source_name
) {
  first_treated_rows <- panel |>
    dplyr::filter(.data[[treatment_column]] == 1L) |>
    dplyr::group_by(.data$point_id) |>
    dplyr::slice_min(
      .data$reference_date,
      n = 1L,
      with_ties = FALSE
    ) |>
    dplyr::ungroup()

  if (identical(treatment_column, "phase1_treated")) {
    treatment_assignments <- first_treated_rows |>
      dplyr::transmute(
        point_id = .data$point_id,
        first_treated_reference_date = .data$reference_date,
        first_treated_year = .data$source_year,
        treatment_stop_id = .data$phase1_stop_id,
        treatment_distance_m = .data$phase1_distance_m
      )
  } else {
    treatment_assignments <- first_treated_rows |>
      dplyr::transmute(
        point_id = .data$point_id,
        first_treated_reference_date = .data$reference_date,
        first_treated_year = .data$source_year,
        treatment_stop_id = .data$nearest_active_stop_id,
        treatment_distance_m = .data$nearest_active_stop_distance_m
      )
  }

  pre_treatment_rows <- panel |>
    dplyr::inner_join(
      treatment_assignments,
      by = "point_id"
    ) |>
    dplyr::filter(
      .data$reference_date < .data$first_treated_reference_date
    )

  pre_treatment_trends <- pre_treatment_rows |>
    dplyr::group_by(.data$point_id) |>
    dplyr::summarise(
      pre_treatment_year_count = dplyr::n(),
      pre_treatment_log_price_slope = calculate_log_price_slope(
        .data$source_year,
        .data$log_price
      ),
      recent_pre_treatment_log_price_slope = calculate_log_price_slope(
        .data$source_year[
          .data$source_year >= .data$first_treated_year - 5L
        ],
        .data$log_price[
          .data$source_year >= .data$first_treated_year - 5L
        ]
      ),
      .groups = "drop"
    )

  baseline_attributes <- pre_treatment_rows |>
    dplyr::group_by(.data$point_id) |>
    dplyr::slice_max(
      .data$reference_date,
      n = 1L,
      with_ties = FALSE
    ) |>
    dplyr::ungroup() |>
    dplyr::transmute(
      point_id = .data$point_id,
      baseline_year = .data$source_year,
      location = .data$location,
      baseline_price_yen_per_m2 = .data$price_yen_per_m2,
      current_use_raw = .data$current_use_raw,
      surrounding_land_use_raw = .data$surrounding_land_use_raw,
      nearest_transport_name_raw = .data$nearest_transport_name_raw,
      transport_distance_m = .data$transport_distance_m,
      use_district_raw = .data$use_district_raw,
      front_road_width_m = .data$front_road_width_m,
      building_coverage_pct = .data$building_coverage_pct,
      floor_area_ratio_pct = .data$floor_area_ratio_pct
    )

  extract_multisynth_unit_average_att(summary_object) |>
    dplyr::left_join(
      summarise_multisynth_unit_pre_fit(summary_object),
      by = "point_id"
    ) |>
    dplyr::left_join(
      treatment_assignments,
      by = "point_id"
    ) |>
    dplyr::left_join(
      pre_treatment_trends,
      by = "point_id"
    ) |>
    dplyr::left_join(
      baseline_attributes,
      by = "point_id"
    ) |>
    dplyr::mutate(
      specification = specification,
      source = source_name,
      point_label = sub(".*_", "", .data$point_id),
      .before = 1L
    )
}

build_heterogeneity_by_source <- function(
  panels_by_source,
  summaries_by_source,
  treatment_column,
  specification
) {
  purrr::imap_dfr(
    panels_by_source,
    function(panel, source_name) {
      build_multisynth_unit_heterogeneity(
        panel = panel,
        summary_object = summaries_by_source[[source_name]],
        treatment_column = treatment_column,
        specification = specification,
        source_name = source_name
      )
    }
  )
}

phase1_unit_att_heterogeneity <- dplyr::bind_rows(
  build_heterogeneity_by_source(
    phase1_model_panels_by_source,
    phase1_summaries_by_source,
    "phase1_treated",
    "phase1_primary_2000_2015"
  ),
  build_heterogeneity_by_source(
    phase1_supplementary_panels_by_source,
    phase1_supplementary_summaries_by_source,
    "phase1_treated",
    "phase1_supplementary_2000_2017"
  ),
  purrr::imap_dfr(
    phase1_sensitivity_panels_by_specification,
    function(panels_by_source, specification) {
      build_heterogeneity_by_source(
        panels_by_source,
        phase1_sensitivity_summaries_by_specification[[specification]],
        "phase1_treated",
        paste0("phase1_sensitivity_", specification)
      )
    }
  )
)

active_stop_unit_att_heterogeneity <- build_heterogeneity_by_source(
  active_stop_proximity_model_panels_by_source,
  active_stop_proximity_summaries_by_source,
  "within_active_stop_radius",
  "active_stop_proximity_2000_2025"
)

unit_att_heterogeneity <- dplyr::bind_rows(
  phase1_unit_att_heterogeneity,
  active_stop_unit_att_heterogeneity
)

heterogeneity_numeric_features <- c(
  "treatment_distance_m",
  "transport_distance_m",
  "baseline_price_yen_per_m2",
  "front_road_width_m",
  "building_coverage_pct",
  "floor_area_ratio_pct",
  "pre_treatment_log_price_slope",
  "recent_pre_treatment_log_price_slope",
  "pre_treatment_fit_rmse"
)

summarise_heterogeneity_feature_associations <- function(data) {
  purrr::map_dfr(
    heterogeneity_numeric_features,
    function(feature_name) {
      complete <- data |>
        dplyr::filter(
          !is.na(.data$unit_average_att),
          !is.na(.data[[feature_name]])
        )

      rank_correlation <- if (
        nrow(complete) >= 3L &&
          dplyr::n_distinct(complete[[feature_name]]) >= 2L
      ) {
        stats::cor(
          complete$unit_average_att,
          complete[[feature_name]],
          method = "spearman"
        )
      } else {
        NA_real_
      }

      tibble::tibble(
        feature = feature_name,
        point_count = nrow(complete),
        spearman_rank_correlation = rank_correlation
      )
    }
  )
}

# These correlations are exploratory effect-modification diagnostics. With
# four to eight treated points per source and specification, they are not
# estimates of a systematic causal mechanism and no p-values are reported.
heterogeneity_feature_associations <- unit_att_heterogeneity |>
  dplyr::group_by(.data$specification, .data$source) |>
  dplyr::group_modify(
    \(data, keys) summarise_heterogeneity_feature_associations(data)
  ) |>
  dplyr::ungroup()

unit_att_heterogeneity
heterogeneity_feature_associations

att_distance_heterogeneity_plot <- unit_att_heterogeneity |>
  ggplot2::ggplot(
    ggplot2::aes(
      x = .data$treatment_distance_m,
      y = .data$unit_average_att,
      label = .data$point_label
    )
  ) +
  ggplot2::geom_hline(yintercept = 0, linetype = 2) +
  ggplot2::geom_point() +
  ggplot2::geom_text(nudge_y = 0.001, check_overlap = TRUE) +
  ggplot2::facet_grid(
    specification ~ source,
    scales = "free"
  ) +
  ggplot2::labs(
    x = "Distance to assigned treatment stop (m)",
    y = "Treated-point average ATT",
    title = "Exploratory treated-point ATT heterogeneity",
    subtitle = paste(
      "Labels are point_id suffixes; associations are descriptive",
      "because each panel has few treated points"
    )
  ) +
  ggplot2::theme_bw()

print(att_distance_heterogeneity_plot)

# nolint end
