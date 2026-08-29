source(here::here("R", "functions.R"))

# The Phase I periods below follow decision 0007. The treatment radius and
# covariate specification remain exploratory rather than adopted settings.
point_match_tolerance_m <- 10
treatment_radius_m <- 1500
metric_crs <- 6677
phase1_primary_panel_years <- 2000:2015
phase1_supp_panel_years <- 2000:2017
phase1_start_year_sensitivity <- list(
  start_2005 = 2005:2015,
  start_2009 = 2009:2015
)
active_access_panel_years <- 2000:2025
baseline_year <- 2010L
baseline_covariate_columns <- character()
# Candidate core columns include area_m2, current_use_raw,
# transport_distance_m, building_coverage_pct, and floor_area_ratio_pct.
# Check their meaning, availability, and pre-treatment timing before use.

stops <- sf::st_read(
  here::here("data", "processed", "brt_stops.gpkg"),
  quiet = TRUE
)
service_interruptions <- readr::read_csv(
  here::here("data", "manual", "brt_stop_service_interruptions.csv"),
  col_types = readr::cols(
    stop_id = readr::col_character(),
    inactive_start_date = readr::col_date(),
    inactive_end_date = readr::col_date(),
    .default = readr::col_character()
  )
)
access_events <- tibble::tribble(
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

land_price_sources <- list(
  publication = land_price_publication,
  survey = prefectural_land_price_survey
)
land_price_analysis <- purrr::map(
  land_price_sources,
  prepare_land_price_analysis_data,
  point_match_tolerance_m = point_match_tolerance_m,
  metric_crs = metric_crs
)
point_stop_distances <- purrr::map(
  land_price_analysis,
  function(analysis_data) {
    calculate_point_stop_distances(
      analysis_data$point_registry,
      stops,
      metric_crs = metric_crs
    )
  }
)

phase1_stop_ids <- stops |>
  sf::st_drop_geometry() |>
  dplyr::filter(.data$phase1_initial) |>
  dplyr::pull(.data$stop_id)

phase1_exposure <- purrr::map(
  point_stop_distances,
  derive_brt_exposure,
  stops = stops,
  treatment_radius_m = treatment_radius_m,
  eligible_stop_ids = phase1_stop_ids
)
treatment_panels <- purrr::map2(
  land_price_analysis,
  point_stop_distances,
  function(analysis_data, distances) {
    derive_brt_treatment_panel(
      analysis_data$point_year_panel,
      distances,
      stops,
      treatment_radius_m = treatment_radius_m,
      service_interruptions = service_interruptions,
      access_events = access_events
    )
  }
)

# Build a complete panel directly for the requested years. In particular, the
# Phase I samples are not conditioned on a point remaining observed through
# 2025.
build_complete_model_panels <- function(panel_years) {
  purrr::map2(
    treatment_panels,
    phase1_exposure,
    function(treatment_panel, exposure) {
      filter_complete_point_panel(
        treatment_panel,
        years = panel_years
      ) |>
        dplyr::left_join(
          exposure |>
            dplyr::rename(
              phase1_exposed = "exposed",
              phase1_stop_id = "stop_id",
              phase1_opening_date = "opening_date",
              phase1_distance_m = "distance_m"
            ),
          by = "point_id"
        ) |>
        dplyr::mutate(
          phase1_treated = as.integer(
            .data$phase1_exposed &
              .data$reference_date >= .data$phase1_opening_date
          ),
          log_price = log(.data$price_yen_per_m2)
        ) |>
        sf::st_drop_geometry()
    }
  )
}

phase1_model_panels <- build_complete_model_panels(
  phase1_primary_panel_years
)
phase1_supp_model_panels <- build_complete_model_panels(
  phase1_supp_panel_years
)
phase1_start_sens_panels <- purrr::map(
  phase1_start_year_sensitivity,
  build_complete_model_panels
)
active_access_model_panels <- build_complete_model_panels(
  active_access_panel_years
)
baseline_covariates <- purrr::map(
  land_price_analysis,
  function(analysis_data) {
    build_baseline_covariates(
      analysis_data$point_year_panel,
      baseline_year = baseline_year,
      columns = baseline_covariate_columns
    )
  }
)

active_access_model_panels <- purrr::imap(
  active_access_model_panels,
  function(panel, source_name) {
    assert_brt_access_is_monotone(
      panel,
      source_label = source_name
    ) |>
      dplyr::mutate(
        brt_access_active = as.integer(.data$brt_access_active)
      )
  }
)
active_access_diagnostics <- purrr::imap_dfr(
  active_access_model_panels,
  function(panel, source_name) {
    panel |>
      dplyr::group_by(.data$point_id) |>
      dplyr::summarise(
        access_reference_date = if (any(.data$brt_access_active == 1L)) {
          min(.data$reference_date[.data$brt_access_active == 1L])
        } else {
          as.Date(NA)
        },
        .groups = "drop"
      ) |>
      dplyr::count(
        .data$access_reference_date,
        name = "point_count",
        .drop = FALSE
      ) |>
      dplyr::mutate(source = source_name, .before = 1L)
  }
)

summarise_phase1_samples <- function(panels, specification) {
  purrr::imap_dfr(
    panels,
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
    phase1_model_panels,
    "primary_2000_2015"
  ),
  summarise_phase1_samples(
    phase1_supp_model_panels,
    "supplementary_2000_2017"
  ),
  purrr::imap_dfr(
    phase1_start_sens_panels,
    \(panels, specification) {
      summarise_phase1_samples(panels, specification)
    }
  )
)

phase1_sample_diagnostics

fit_multisynth_panels <- function(panels, treatment_column) {
  model_formula <- stats::reformulate(
    treatment_column,
    response = "log_price"
  )

  purrr::map(
    panels,
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

summarise_multisynth_panels <- function(fits) {
  purrr::map(
    fits,
    summary,
    inf_type = "jackknife"
  )
}

phase1_fits <- fit_multisynth_panels(
  phase1_model_panels,
  "phase1_treated"
)
phase1_summaries <- summarise_multisynth_panels(phase1_fits)
phase1_summaries
purrr::walk(
  phase1_summaries,
  \(x) print(plot(x))
)

supplementary_phase1_fits <- fit_multisynth_panels(
  phase1_supp_model_panels,
  "phase1_treated"
)
supplementary_phase1_summaries <- summarise_multisynth_panels(
  supplementary_phase1_fits
)
supplementary_phase1_summaries
purrr::walk(
  supplementary_phase1_summaries,
  \(x) print(plot(x))
)

phase1_start_sens_fits <- purrr::map(
  phase1_start_sens_panels,
  fit_multisynth_panels,
  treatment_column = "phase1_treated"
)
phase1_start_sens_summaries <- purrr::map(
  phase1_start_sens_fits,
  summarise_multisynth_panels
)
phase1_start_sens_summaries
purrr::walk(
  phase1_start_sens_summaries,
  \(summaries) purrr::walk(summaries, \(x) print(plot(x)))
)

active_access_diagnostics

active_access_fits <- fit_multisynth_panels(
  active_access_model_panels,
  "brt_access_active"
)

active_access_summaries <- summarise_multisynth_panels(
  active_access_fits
)
active_access_summaries
purrr::walk(
  active_access_summaries,
  \(x) print(plot(x))
)

# a <- active_access_model_panels$survey |>
#   dplyr::filter(brt_access_active == 1) |>
#   dplyr::group_by(point_id) |>
#   dplyr::slice_min(source_year, n = 1, with_ties = FALSE) |>
#   dplyr::ungroup()
# 
# active_access_summaries$survey$att |> 
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

summarise_average_atts <- function(summaries, specification) {
  purrr::imap_dfr(
    summaries,
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
    phase1_summaries,
    "primary_2000_2015"
  ),
  summarise_average_atts(
    supplementary_phase1_summaries,
    "supplementary_2000_2017"
  ),
  purrr::imap_dfr(
    phase1_start_sens_summaries,
    \(summaries, specification) {
      summarise_average_atts(summaries, specification)
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
  phase1_model_panels,
  function(panel, source_name) {
    run_multisynth_loo(
      panel = panel,
      source_name = source_name,
      reference_summary = phase1_summaries[[source_name]],
      treatment_column = "phase1_treated"
    )
  }
)

phase1_loo_results


# -------------------------------------------------------------------------
# 2. Supplementary Phase 1 specification (through 2017)
# -------------------------------------------------------------------------

phase1_supp_loo_results <- purrr::imap_dfr(
  phase1_supp_model_panels,
  function(panel, source_name) {
    run_multisynth_loo(
      panel = panel,
      source_name = source_name,
      reference_summary = supplementary_phase1_summaries[[source_name]],
      treatment_column = "phase1_treated"
    )
  }
)

phase1_supp_loo_results


# -------------------------------------------------------------------------
# 3. All active-access events
# -------------------------------------------------------------------------

active_access_loo_results <- purrr::imap_dfr(
  active_access_model_panels,
  function(panel, source_name) {
    run_multisynth_loo(
      panel = panel,
      source_name = source_name,
      reference_summary = active_access_summaries[[source_name]],
      treatment_column = "brt_access_active"
    )
  }
)

active_access_loo_results


# -------------------------------------------------------------------------
# Combine all LOO results
# -------------------------------------------------------------------------

loo_results <- dplyr::bind_rows(
  phase1_loo_results |>
    dplyr::mutate(
      specification = "phase1_primary_2000_2015",
      .before = 1L
    ),
  phase1_supp_loo_results |>
    dplyr::mutate(
      specification = "phase1_supplementary_2000_2017",
      .before = 1L
    ),
  active_access_loo_results |>
    dplyr::mutate(
      specification = "active_access",
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
  
