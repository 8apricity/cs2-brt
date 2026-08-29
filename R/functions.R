.data <- NULL
.env <- NULL

land_price_mappings <- local({
  cached <- NULL
  function(refresh = FALSE) {
    if (is.null(cached) || refresh) {
      path <- here::here("config", "land_price_mappings.yml")
      if (!file.exists(path)) {
        stop("Missing land-price mapping file: ", path, call. = FALSE)
      }
      cached <<- yaml::read_yaml(path)
    }
    cached
  }
})

land_price_dataset_spec <- function(dataset) {
  dataset_config <- land_price_mappings()$datasets[[dataset]]
  if (is.null(dataset_config)) {
    stop("Unsupported land-price dataset: ", dataset, call. = FALSE)
  }
  list(
    prefix = dataset_config$prefix,
    feature_names = unlist(dataset_config$feature_names, use.names = FALSE),
    price_tags = unlist(dataset_config$price_tags, use.names = FALSE),
    code_tags = unlist(dataset_config$code_tags, use.names = FALSE),
    reference_month = as.integer(dataset_config$reference_month),
    reference_day = as.integer(dataset_config$reference_day)
  )
}

xml_local_name <- function(node) {
  xml2::xml_name(node)
}

xml_direct_children_named <- function(node, names) {
  children <- xml2::xml_children(node)
  children[vapply(children, xml_local_name, character(1)) %in% names]
}

xml_nonempty_text <- function(nodes) {
  if (length(nodes) == 0L) {
    return(character(0))
  }

  values <- trimws(xml2::xml_text(nodes))
  values[nzchar(values)]
}

xml_first_direct_text <- function(node, names) {
  values <- xml_nonempty_text(xml_direct_children_named(node, names))
  if (length(values) == 0L) NA_character_ else values[[1L]]
}

xml_all_direct_text <- function(node, names) {
  xml_nonempty_text(xml_direct_children_named(node, names))
}

xml_first_descendant_text <- function(node, names) {
  descendants <- xml2::xml_find_all(node, ".//*")
  descendants <- descendants[
    vapply(descendants, xml_local_name, character(1)) %in% names
  ]
  values <- xml_nonempty_text(descendants)
  if (length(values) == 0L) NA_character_ else values[[1L]]
}

xml_first_attribute_ending <- function(node, suffix) {
  attributes <- xml2::xml_attrs(node)
  if (length(attributes) == 0L) {
    return(NA_character_)
  }

  attribute_names <- names(attributes)
  matched <- endsWith(attribute_names, suffix)
  if (!any(matched)) NA_character_ else unname(attributes[matched][[1L]])
}

as_number_or_na <- function(value) {
  if (length(value) == 0L || is.na(value) || !nzchar(value)) {
    return(NA_real_)
  }

  suppressWarnings(as.numeric(value))
}

as_integer_or_na <- function(value) {
  number <- as_number_or_na(value)
  if (is.na(number)) NA_integer_ else as.integer(number)
}

land_price_schema_era <- function(dataset, year) {
  eras <- land_price_mappings()$datasets[[dataset]]$schema_eras
  matched <- Filter(function(era) {
    year >= era$from && year <= era$to
  }, eras)
  if (length(matched) != 1L) {
    stop("Unsupported schema year: ", dataset, " ", year, call. = FALSE)
  }
  matched[[1L]]$name
}

land_price_source_crs <- function(dataset, year) {
  periods <- land_price_mappings()$datasets[[dataset]]$source_crs
  matched <- Filter(function(period) {
    year >= period$from && year <= period$to
  }, periods)
  if (length(matched) != 1L) {
    stop("Unsupported CRS year: ", dataset, " ", year, call. = FALSE)
  }
  as.integer(matched[[1L]]$epsg)
}

land_price_reference_date <- function(dataset, year) {
  spec <- land_price_dataset_spec(dataset)
  as.Date(sprintf(
    "%04d-%02d-%02d",
    year,
    spec$reference_month,
    spec$reference_day
  ))
}

land_price_feature_nodes <- function(document, spec) {
  all_nodes <- xml2::xml_find_all(document, "//*")
  node_names <- vapply(all_nodes, xml_local_name, character(1))
  candidates <- all_nodes[node_names %in% spec$feature_names]

  candidates[vapply(candidates, function(node) {
    child_names <- vapply(
      xml2::xml_children(node),
      xml_local_name,
      character(1)
    )
    any(child_names %in% spec$price_tags)
  }, logical(1))]
}

xml_id_index <- function(document) {
  nodes <- xml2::xml_find_all(document, "//*")
  node_names <- vapply(nodes, xml_local_name, character(1))
  nodes <- nodes[node_names == "Point"]
  ids <- vapply(nodes, xml_first_attribute_ending, character(1), suffix = "id")
  keep <- !is.na(ids) & nzchar(ids)
  stats::setNames(as.list(nodes[keep]), ids[keep])
}

land_price_coordinate <- function(feature, id_index) {
  position_nodes <- xml_direct_children_named(feature, c("position", "pos"))
  if (length(position_nodes) == 0L) {
    point_nodes <- xml_direct_children_named(feature, c("Point"))
  } else {
    reference <- xml_first_attribute_ending(position_nodes[[1L]], "href")
    reference <- sub("^#", "", reference)
    point_nodes <- if (!is.na(reference) && reference %in% names(id_index)) {
      id_index[[reference]]
    } else {
      position_nodes
    }
  }

  coordinate_nodes <- xml2::xml_find_all(point_nodes, ".//*")
  coordinate_names <- vapply(
    coordinate_nodes,
    xml_local_name,
    character(1)
  )
  coordinate_nodes <- coordinate_nodes[
    coordinate_names %in% c("pos", "position", "coordinate")
  ]
  values <- xml_nonempty_text(coordinate_nodes)
  if (length(values) == 0L) {
    values <- xml_nonempty_text(point_nodes)
  }
  if (length(values) == 0L) {
    stop("A feature has no readable point coordinate.", call. = FALSE)
  }

  parts <- strsplit(values[[1L]], "[[:space:],]+")[[1L]]
  parts <- parts[nzchar(parts)]
  if (length(parts) != 2L) {
    stop("Expected a latitude/longitude coordinate pair.", call. = FALSE)
  }

  c(latitude = as.numeric(parts[[1L]]), longitude = as.numeric(parts[[2L]]))
}

land_price_code_parts <- function(feature, spec) {
  containers <- xml_direct_children_named(feature, spec$code_tags)
  index_number <- xml_first_direct_text(feature, c("indexNumber", "idn"))
  sequence_number <- xml_first_direct_text(feature, c("sequenceNumber", "rls"))

  if (length(containers) > 0L) {
    if (is.na(index_number)) {
      index_number <- xml_first_descendant_text(
        containers[[1L]],
        c("indexNumber", "idn")
      )
    }
    if (is.na(sequence_number)) {
      sequence_number <- xml_first_descendant_text(
        containers[[1L]],
        c("sequenceNumber", "rls")
      )
    }
  }

  list(
    index_number = index_number,
    sequence_number = sequence_number
  )
}

land_price_core_root_names <- function(spec) {
  unique(c(
    spec$price_tags,
    spec$code_tags,
    "previousRepresentedLandCode",
    "previousStandardLandCode",
    "year",
    "ye3",
    "position",
    "pos",
    "Point",
    "indexNumber",
    "idn",
    "sequenceNumber",
    "rls",
    "administrativeAreaCode",
    "aac",
    "cityName",
    "cnl",
    "location",
    "address",
    "as1",
    "acreage",
    "ac1",
    "currentUse",
    "pu1",
    "usageDescription",
    "ud1",
    "usageClassification",
    "buildingStructure",
    "bs1",
    "waterFacility",
    "waf",
    "gasFacility",
    "gaf",
    "sewageFacility",
    "sef",
    "configuration",
    "frontageRatio",
    "depthRatio",
    "numberOfFloors",
    "numberOfBasementFloors",
    "frontalRoad",
    "directionOfFrontalRoad",
    "widthOfFrontalRoad",
    "stationSquareOfFrontalRoad",
    "pavementOfFrontalRoad",
    "sideRoad",
    "directionOfSideRoad",
    "proximityWithTransportationFacility",
    "surroundingPresentUsage",
    "nameOfNearestStation",
    "nns",
    "distanceFromStation",
    "ds1",
    "restrictionByCityPlanningLaw",
    "rcl",
    "useDistrict",
    "fireArea",
    "urbanPlanningArea",
    "forestLaw",
    "parksLaw",
    "buildingCoverage",
    "bc1",
    "floorAreaRatio",
    "fr1",
    "extraFloorAreaRatio"
  ))
}

empty_land_price_attributes <- function() {
  data.frame(
    observation_id = character(0),
    source_dataset = character(0),
    source_year = integer(0),
    attribute_name = character(0),
    attribute_path = character(0),
    value_index = integer(0),
    raw_value = character(0),
    stringsAsFactors = FALSE
  )
}

xml_leaf_nodes <- function(node) {
  children <- xml2::xml_children(node)
  if (length(children) == 0L) {
    return(list(node))
  }
  unlist(lapply(children, xml_leaf_nodes), recursive = FALSE)
}

binary_reported_value <- function(raw_value) {
  if (is.na(raw_value)) {
    return(NA)
  }
  normalized <- tolower(trimws(raw_value))
  if (normalized %in% c("1", "true")) {
    TRUE
  } else if (normalized %in% c("0", "false")) {
    FALSE
  } else {
    NA
  }
}

normalize_building_structure <- function(raw_value, floors_above, floors_below) {
  result <- list(
    material = NA_character_,
    floors_above = floors_above,
    floors_below = floors_below,
    status = if (is.na(raw_value)) NA_character_ else "unmapped"
  )
  if (is.na(raw_value) || !nzchar(raw_value)) {
    return(result)
  }

  material_match <- regexpr(
    "^(SRC|RC|LS|S|W|B|\u305d\u306e\u4ed6)",
    raw_value,
    perl = TRUE
  )
  if (material_match[[1L]] == -1L) {
    return(result)
  }

  result$material <- regmatches(raw_value, material_match)
  suffix <- substring(raw_value, attr(material_match, "match.length") + 1L)
  if (!nzchar(suffix)) {
    result$status <- "reported_material"
    return(result)
  }

  if (grepl("^[0-9]+$", suffix)) {
    result$floors_above <- as.integer(suffix)
    result$status <- "parsed_legacy"
    return(result)
  }

  matched <- regexec("^([0-9]+)F(?:([0-9]+)B)?$", suffix, perl = TRUE)
  parts <- regmatches(suffix, matched)[[1L]]
  if (length(parts) > 0L) {
    result$floors_above <- as.integer(parts[[2L]])
    result$floors_below <- if (
      length(parts) >= 3L && nzchar(parts[[3L]])
    ) {
      as.integer(parts[[3L]])
    } else {
      0L
    }
    result$status <- "parsed_legacy"
  }
  result
}

normalize_usage_class <- function(dataset, raw_value) {
  if (is.na(raw_value)) {
    return(NA_character_)
  }
  normalized <- coarse_code_lookup("usage_class", raw_value)
  if (
    identical(normalized, "other_open_land") &&
      dataset != "land_price_publication"
  ) {
    return(NA_character_)
  }
  normalized
}

normalization_status <- function(raw_value, normalized_value) {
  if (is.na(raw_value) || !nzchar(trimws(raw_value))) {
    NA_character_
  } else if (is.na(normalized_value)) {
    "unmapped"
  } else {
    "mapped"
  }
}

normalize_shape_class <- function(raw_value) {
  if (is.na(raw_value)) {
    return(NA_character_)
  }
  coarse_code_lookup("shape", raw_value)
}

coarse_code_lookup <- function(group, raw_value) {
  mappings <- land_price_mappings()$coarse_codes[[group]]
  matched <- names(mappings)[vapply(mappings, function(values) {
    raw_value %in% unlist(values, use.names = FALSE)
  }, logical(1))]
  if (length(matched) == 1L) matched[[1L]] else NA_character_
}

normalize_road_class <- function(raw_value) {
  if (is.na(raw_value)) {
    return(NA_character_)
  }
  coded <- coarse_code_lookup("front_road", raw_value)
  if (!is.na(coded)) {
    coded
  } else if (grepl("\u56fd\u9053", raw_value, fixed = TRUE)) {
    "national"
  } else if (
    grepl(
      "\u90fd\u9053|\u9053\u9053|\u5e9c\u9053|\u770c\u9053|\u90fd\u9053\u5e9c\u770c\u9053",
      raw_value
    )
  ) {
    "prefectural"
  } else if (
    grepl(
      "\u5e02\u9053|\u533a\u9053|\u753a\u9053|\u6751\u9053|\u5e02\u533a\u753a\u6751\u9053",
      raw_value
    )
  ) {
    "municipal"
  } else if (grepl("\u79c1\u9053", raw_value, fixed = TRUE)) {
    "private"
  } else if (grepl("\u533a\u753b\u8857\u8def", raw_value, fixed = TRUE)) {
    "planned_street"
  } else if (grepl("\u8fb2\u9053|\u6797\u9053|\u9053\u8def", raw_value)) {
    "other_road"
  } else {
    NA_character_
  }
}

normalize_reported_measure <- function(raw_value) {
  number <- as_number_or_na(raw_value)
  if (is.na(number)) {
    list(value = NA_real_, status = NA_character_)
  } else if (number == 0) {
    list(value = NA_real_, status = "not_reported_or_not_applicable")
  } else {
    list(value = number, status = "reported")
  }
}

normalize_road_width <- function(dataset, year, raw_value) {
  number <- as_number_or_na(raw_value)
  if (is.na(number)) {
    return(list(value = NA_real_, status = NA_character_))
  }
  sentinels <- land_price_mappings()$sentinels$front_road_width
  sentinel_status <- sentinels[[as.character(number)]]
  if (!is.null(sentinel_status)) {
    return(list(value = NA_real_, status = sentinel_status))
  }
  status <- if (
    dataset == "prefectural_land_price_survey" && year == 2013L
  ) {
    land_price_mappings()$exceptions$
      prefectural_land_price_survey_2013_road_width$status
  } else {
    "reported_m"
  }
  list(value = number, status = status)
}

normalize_transport_distance <- function(dataset, raw_value) {
  number <- as_number_or_na(raw_value)
  if (is.na(number)) {
    return(list(value = NA_real_, status = NA_character_))
  }
  if (dataset == "prefectural_land_price_survey") {
    sentinels <- land_price_mappings()$sentinels$
      prefectural_transport_distance
    sentinel_status <- sentinels[[as.character(number)]]
    if (!is.null(sentinel_status)) {
      return(list(value = NA_real_, status = sentinel_status))
    }
  }
  list(value = number, status = "reported_m")
}

normalize_land_price_row <- function(observation, dataset, year) {
  building <- normalize_building_structure(
    observation$building_structure_raw,
    observation$floors_above,
    observation$floors_below
  )
  observation$building_material <- building$material
  observation$floors_above <- building$floors_above
  observation$floors_below <- building$floors_below
  observation$building_parse_status <- building$status

  observation$usage_class_coarse <- normalize_usage_class(
    dataset,
    observation$usage_class_raw
  )
  observation$usage_class_status <- normalization_status(
    observation$usage_class_raw,
    observation$usage_class_coarse
  )
  observation$water_available_or_supplied <- binary_reported_value(
    observation$water_facility_raw
  )
  observation$water_facility_status <- normalization_status(
    observation$water_facility_raw,
    observation$water_available_or_supplied
  )
  observation$gas_available_or_supplied <- binary_reported_value(
    observation$gas_facility_raw
  )
  observation$gas_facility_status <- normalization_status(
    observation$gas_facility_raw,
    observation$gas_available_or_supplied
  )
  observation$sewage_available_or_supplied <- binary_reported_value(
    observation$sewage_facility_raw
  )
  observation$sewage_facility_status <- normalization_status(
    observation$sewage_facility_raw,
    observation$sewage_available_or_supplied
  )
  observation$shape_class_coarse <- normalize_shape_class(observation$shape_raw)
  observation$shape_mapping_status <- normalization_status(
    observation$shape_raw,
    observation$shape_class_coarse
  )
  observation$front_road_class_coarse <- normalize_road_class(
    observation$front_road_class_raw
  )
  observation$front_road_class_status <- normalization_status(
    observation$front_road_class_raw,
    observation$front_road_class_coarse
  )

  width <- normalize_road_width(
    dataset,
    year,
    observation$front_road_width_raw
  )
  observation$front_road_width_m <- width$value
  observation$front_road_width_status <- width$status

  distance <- normalize_transport_distance(
    dataset,
    observation$transport_distance_raw
  )
  observation$transport_distance_m <- distance$value
  observation$transport_access_status <- distance$status

  coverage <- normalize_reported_measure(observation$building_coverage_pct_raw)
  observation$building_coverage_pct <- coverage$value
  observation$building_coverage_status <- coverage$status
  floor_area_ratio <- normalize_reported_measure(
    observation$floor_area_ratio_pct_raw
  )
  observation$floor_area_ratio_pct <- floor_area_ratio$value
  observation$floor_area_ratio_status <- floor_area_ratio$status

  observation$paved <- if (is.na(observation$pavement_raw)) {
    NA
  } else if (observation$pavement_raw == "\u8217\u88c5") {
    TRUE
  } else if (observation$pavement_raw == "\u672a\u8217\u88c5") {
    FALSE
  } else {
    NA
  }
  observation$pavement_status <- normalization_status(
    observation$pavement_raw,
    observation$paved
  )
  observation$road_contact_class <- NA_character_
  observation$road_contact_status <- normalization_status(
    observation$road_contact_raw,
    observation$road_contact_class
  )
  if (!is.na(observation$nearest_transport_name_raw)) {
    observation$nearest_transport_kind <- "unknown"
  }
  observation$nearest_transport_kind_status <- normalization_status(
    observation$nearest_transport_name_raw,
    if (identical(observation$nearest_transport_kind, "unknown")) {
      NA_character_
    } else {
      observation$nearest_transport_kind
    }
  )
  observation$extra_floor_area_ratio_flag <- binary_reported_value(
    observation$extra_floor_area_ratio_raw
  )
  observation$extra_floor_area_ratio_status <- normalization_status(
    observation$extra_floor_area_ratio_raw,
    observation$extra_floor_area_ratio_flag
  )

  zoning_raw <- c(
    observation$use_district_raw,
    observation$fire_area_raw,
    observation$urban_planning_area_raw,
    observation$forest_law_raw,
    observation$parks_law_raw
  )
  if (any(!is.na(zoning_raw))) {
    observation$zoning_mapping_status <- "unmapped"
  } else if (!is.na(observation$legal_restrictions_raw_json)) {
    observation$zoning_mapping_status <- "legacy_unmapped"
  }
  observation
}

land_price_extra_attributes <- function(
  feature,
  observation_id,
  dataset,
  year,
  spec
) {
  direct_children <- xml2::xml_children(feature)
  direct_names <- vapply(direct_children, xml_local_name, character(1))
  direct_children <- direct_children[
    !direct_names %in% land_price_core_root_names(spec)
  ]

  values_by_root <- lapply(seq_along(direct_children), function(index) {
    root <- direct_children[[index]]
    root_name <- xml_local_name(root)
    leaves <- xml_leaf_nodes(root)
    leaf_names <- vapply(leaves, xml_local_name, character(1))
    values <- trimws(vapply(leaves, xml2::xml_text, character(1)))

    keep <- nzchar(values)
    if (!any(keep)) {
      return(NULL)
    }

    values <- values[keep]
    leaf_names <- leaf_names[keep]
    list(
      attribute_name = if (
        length(leaf_names) == 1L && leaf_names == root_name
      ) {
        root_name
      } else {
        leaf_names
      },
      attribute_path = ifelse(
        leaf_names == root_name,
        root_name,
        paste(root_name, leaf_names, sep = "/")
      ),
      raw_value = values
    )
  })

  values_by_root <- values_by_root[
    !vapply(values_by_root, is.null, logical(1))
  ]
  if (length(values_by_root) == 0L) {
    return(empty_land_price_attributes())
  }

  counts <- vapply(
    values_by_root,
    function(value) length(value$raw_value),
    integer(1)
  )
  data.frame(
    observation_id = rep(observation_id, sum(counts)),
    source_dataset = rep(dataset, sum(counts)),
    source_year = rep(as.integer(year), sum(counts)),
    attribute_name = unlist(
      lapply(values_by_root, `[[`, "attribute_name"),
      use.names = FALSE
    ),
    attribute_path = unlist(
      lapply(values_by_root, `[[`, "attribute_path"),
      use.names = FALSE
    ),
    value_index = sequence(counts),
    raw_value = unlist(
      lapply(values_by_root, `[[`, "raw_value"),
      use.names = FALSE
    ),
    stringsAsFactors = FALSE
  )
}

parse_land_price_xml <- function(file, dataset) {
  spec <- land_price_dataset_spec(dataset)
  document <- suppressWarnings(xml2::read_xml(file))
  features <- land_price_feature_nodes(document, spec)
  if (length(features) == 0L) {
    stop("No land-price observations found in: ", file, call. = FALSE)
  }

  id_index <- xml_id_index(document)
  parsed <- lapply(seq_along(features), function(feature_index) {
    feature <- features[[feature_index]]
    year_node <- xml_direct_children_named(feature, c("year", "ye3"))
    year <- if (length(year_node) == 0L) {
      NA_integer_
    } else {
      as_integer_or_na(
        xml_first_descendant_text(year_node[[1L]], c("timePosition"))
      )
    }
    if (is.na(year)) {
      year <- as_integer_or_na(
        xml_first_direct_text(feature, c("year", "ye3"))
      )
    }

    code <- land_price_code_parts(feature, spec)
    administrative_area_code <- xml_first_direct_text(
      feature,
      c("administrativeAreaCode", "aac")
    )
    if (is.na(administrative_area_code)) {
      code_containers <- xml_direct_children_named(feature, spec$code_tags)
      if (length(code_containers) > 0L) {
        administrative_area_code <- xml_first_descendant_text(
          code_containers[[1L]],
          "administrativeAreaCode"
        )
      }
    }
    uses_location <- (
      dataset == "land_price_publication" && year >= 2022L
    ) || (
      dataset == "prefectural_land_price_survey" && year >= 2021L
    )
    location <- if (uses_location) {
      xml_first_direct_text(feature, "location")
    } else {
      xml_first_direct_text(feature, c("address", "as1"))
    }
    residential_address <- if (uses_location) {
      xml_first_direct_text(feature, "address")
    } else {
      NA_character_
    }
    source_feature_id <- xml_first_attribute_ending(feature, "id")
    if (is.na(source_feature_id)) {
      source_feature_id <- paste0("row-", feature_index)
    }
    observation_id <- paste(
      dataset,
      year,
      administrative_area_code,
      code$index_number,
      code$sequence_number,
      source_feature_id,
      sep = ":"
    )
    coordinate <- land_price_coordinate(feature, id_index)
    current_use_elements <- xml_all_direct_text(
      feature,
      c("currentUse", "pu1")
    )
    current_use_values <- trimws(unlist(
      strsplit(current_use_elements, ",", fixed = TRUE),
      use.names = FALSE
    ))
    current_use_values <- current_use_values[nzchar(current_use_values)]
    current_use_raw <- if (length(current_use_elements) == 0L) {
      NA_character_
    } else {
      paste(current_use_elements, collapse = ",")
    }
    current_use_json <- if (length(current_use_values) == 0L) {
      NA_character_
    } else {
      as.character(jsonlite::toJSON(current_use_values, auto_unbox = FALSE))
    }

    observation <- data.frame(
      observation_id = observation_id,
      source_dataset = dataset,
      source_year = as.integer(year),
      reference_date = land_price_reference_date(dataset, year),
      source_schema_era = land_price_schema_era(dataset, year),
      source_file = normalizePath(file, winslash = "/", mustWork = FALSE),
      source_feature_id = source_feature_id,
      administrative_area_code = administrative_area_code,
      point_index_number = code$index_number,
      point_sequence_number = code$sequence_number,
      city_name = xml_first_direct_text(feature, c("cityName", "cnl")),
      location = location,
      residential_address = residential_address,
      price_yen_per_m2 = as_number_or_na(
        xml_first_direct_text(feature, spec$price_tags)
      ),
      area_m2 = as_number_or_na(
        xml_first_direct_text(feature, c("acreage", "ac1"))
      ),
      current_use_raw = current_use_raw,
      current_use_json = current_use_json,
      current_use_status = if (is.na(current_use_json)) NA_character_ else "reported",
      current_use_detail_raw = xml_first_direct_text(
        feature,
        c("usageDescription", "ud1")
      ),
      usage_class_raw = xml_first_direct_text(feature, "usageClassification"),
      usage_class_coarse = NA_character_,
      usage_class_status = NA_character_,
      building_structure_raw = xml_first_direct_text(
        feature,
        c("buildingStructure", "bs1")
      ),
      building_material = NA_character_,
      floors_above = as_integer_or_na(
        xml_first_direct_text(feature, "numberOfFloors")
      ),
      floors_below = as_integer_or_na(
        xml_first_direct_text(feature, "numberOfBasementFloors")
      ),
      building_parse_status = NA_character_,
      water_facility_raw = xml_first_direct_text(
        feature,
        c("waterFacility", "waf")
      ),
      water_available_or_supplied = NA,
      water_facility_status = NA_character_,
      gas_facility_raw = xml_first_direct_text(
        feature,
        c("gasFacility", "gaf")
      ),
      gas_available_or_supplied = NA,
      gas_facility_status = NA_character_,
      sewage_facility_raw = xml_first_direct_text(
        feature,
        c("sewageFacility", "sef")
      ),
      sewage_available_or_supplied = NA,
      sewage_facility_status = NA_character_,
      shape_raw = xml_first_direct_text(feature, "configuration"),
      shape_class_coarse = NA_character_,
      shape_mapping_status = NA_character_,
      frontage_ratio = as_number_or_na(
        xml_first_direct_text(feature, "frontageRatio")
      ),
      depth_ratio = as_number_or_na(
        xml_first_direct_text(feature, "depthRatio")
      ),
      front_road_class_raw = xml_first_direct_text(feature, "frontalRoad"),
      front_road_class_coarse = NA_character_,
      front_road_class_status = NA_character_,
      front_road_direction = xml_first_direct_text(
        feature,
        "directionOfFrontalRoad"
      ),
      front_road_width_raw = xml_first_direct_text(
        feature,
        "widthOfFrontalRoad"
      ),
      front_road_width_m = NA_real_,
      front_road_width_status = NA_character_,
      pavement_raw = xml_first_direct_text(feature, "pavementOfFrontalRoad"),
      paved = NA,
      pavement_status = NA_character_,
      road_contact_raw = xml_first_direct_text(feature, "sideRoad"),
      road_contact_class = NA_character_,
      road_contact_status = NA_character_,
      side_road_direction = xml_first_direct_text(
        feature,
        "directionOfSideRoad"
      ),
      surrounding_land_use_raw = xml_first_direct_text(
        feature,
        "surroundingPresentUsage"
      ),
      nearest_transport_name_raw = xml_first_direct_text(
        feature,
        c("nameOfNearestStation", "nns")
      ),
      nearest_transport_kind = NA_character_,
      nearest_transport_kind_status = NA_character_,
      transport_distance_raw = xml_first_direct_text(
        feature,
        c("distanceFromStation", "ds1")
      ),
      transport_distance_m = NA_real_,
      transport_access_status = NA_character_,
      legal_restrictions_raw_json = NA_character_,
      use_district_raw = xml_first_direct_text(feature, "useDistrict"),
      use_district_code = NA_character_,
      fire_area_raw = xml_first_direct_text(feature, "fireArea"),
      fire_area_code = NA_character_,
      urban_planning_area_raw = xml_first_direct_text(
        feature,
        "urbanPlanningArea"
      ),
      urban_planning_area_code = NA_character_,
      forest_law_raw = xml_first_direct_text(feature, "forestLaw"),
      forest_law_code = NA_character_,
      parks_law_raw = xml_first_direct_text(feature, "parksLaw"),
      parks_law_code = NA_character_,
      zoning_mapping_status = NA_character_,
      building_coverage_pct_raw = xml_first_direct_text(
        feature,
        c("buildingCoverage", "bc1")
      ),
      building_coverage_pct = NA_real_,
      building_coverage_status = NA_character_,
      floor_area_ratio_pct_raw = xml_first_direct_text(
        feature,
        c("floorAreaRatio", "fr1")
      ),
      floor_area_ratio_pct = NA_real_,
      floor_area_ratio_status = NA_character_,
      extra_floor_area_ratio_raw = xml_first_direct_text(
        feature,
        "extraFloorAreaRatio"
      ),
      extra_floor_area_ratio_flag = NA,
      extra_floor_area_ratio_status = NA_character_,
      source_latitude = unname(coordinate[["latitude"]]),
      source_longitude = unname(coordinate[["longitude"]]),
      stringsAsFactors = FALSE
    )

    legal <- xml_all_direct_text(
      feature,
      c("restrictionByCityPlanningLaw", "rcl")
    )
    if (length(legal) > 0L) {
      observation$legal_restrictions_raw_json <- as.character(jsonlite::toJSON(
        legal,
        auto_unbox = FALSE
      ))
    }
    observation <- normalize_land_price_row(
      observation,
      dataset,
      year
    )

    list(
      observation = observation,
      attributes = land_price_extra_attributes(
        feature,
        observation_id,
        dataset,
        year,
        spec
      )
    )
  })

  observations <- do.call(rbind, lapply(parsed, `[[`, "observation"))
  source_crs <- unique(vapply(
    observations$source_year,
    land_price_source_crs,
    integer(1),
    dataset = dataset
  ))
  if (length(source_crs) != 1L) {
    stop("One XML file must contain exactly one source CRS.", call. = FALSE)
  }

  observations <- sf::st_as_sf(
    observations,
    coords = c("source_longitude", "source_latitude"),
    crs = source_crs,
    remove = TRUE
  )
  observations <- sf::st_transform(observations, 6668)
  attributes <- do.call(rbind, lapply(parsed, `[[`, "attributes"))
  source_year <- unique(observations$source_year)
  source_metadata <- data.frame(
    source_dataset = dataset,
    source_year = source_year,
    reference_date = land_price_reference_date(dataset, source_year),
    source_schema_era = land_price_schema_era(dataset, source_year),
    source_file = normalizePath(file, winslash = "/", mustWork = FALSE),
    source_crs_epsg = source_crs,
    source_axis_order = "latitude_longitude",
    output_crs_epsg = 6668L,
    observation_count = nrow(observations),
    stringsAsFactors = FALSE
  )

  list(
    observations = observations,
    attributes = attributes,
    source_metadata = source_metadata
  )
}

land_price_known_years <- function(dataset) {
  years <- land_price_mappings()$datasets[[dataset]]$known_years
  if (is.null(years) || length(years) != 2L) {
    land_price_dataset_spec(dataset)
    stop("Missing known-year range for: ", dataset, call. = FALSE)
  }
  seq.int(as.integer(years[[1L]]), as.integer(years[[2L]]))
}

land_price_year_from_filename <- function(file, dataset) {
  spec <- land_price_dataset_spec(dataset)
  pattern <- paste0(
    "^",
    spec$prefix,
    "[-_]([0-9]{2})_08(?:-g)?",
    "(?:_(?:LandPrice|PrefectureLandPriceResearch))?",
    "\\.(?:xml|shp)$"
  )
  matched <- regexec(pattern, basename(file), ignore.case = TRUE)
  parts <- regmatches(basename(file), matched)[[1L]]
  if (length(parts) != 2L) {
    return(NA_integer_)
  }
  short_year <- as.integer(parts[[2L]])
  if (short_year >= 83L) 1900L + short_year else 2000L + short_year
}

discover_land_price_files <- function(raw_dir, dataset, extension) {
  spec <- land_price_dataset_spec(dataset)
  files <- list.files(
    raw_dir,
    pattern = paste0("\\.", extension, "$"),
    recursive = TRUE,
    full.names = TRUE,
    ignore.case = TRUE
  )
  files <- files[grepl(
    paste0("^", spec$prefix, "[-_]"),
    basename(files),
    ignore.case = TRUE
  )]
  if (tolower(extension) == "xml") {
    files <- files[!grepl("^KS-META-", basename(files), ignore.case = TRUE)]
  }
  years <- vapply(
    files,
    land_price_year_from_filename,
    integer(1),
    dataset = dataset
  )
  keep <- !is.na(years)
  files <- files[keep]
  years <- years[keep]
  duplicated_years <- unique(years[duplicated(years)])
  if (length(duplicated_years) > 0L) {
    stop(
      "Multiple ",
      extension,
      " files found for years: ",
      paste(duplicated_years, collapse = ", "),
      call. = FALSE
    )
  }
  stats::setNames(files[order(years)], years[order(years)])
}

validate_expected_years <- function(files, expected_years, dataset, kind) {
  actual_years <- as.integer(names(files))
  missing_years <- setdiff(expected_years, actual_years)
  unexpected_years <- setdiff(actual_years, expected_years)
  if (length(missing_years) > 0L || length(unexpected_years) > 0L) {
    details <- c(
      if (length(missing_years) > 0L) {
        paste0("missing=", paste(missing_years, collapse = ","))
      },
      if (length(unexpected_years) > 0L) {
        paste0("unexpected=", paste(unexpected_years, collapse = ","))
      }
    )
    stop(
      "The ",
      dataset,
      " ",
      kind,
      " year contract failed: ",
      paste(details, collapse = "; "),
      call. = FALSE
    )
  }
  invisible(files)
}

land_price_shapefile_mapping <- function(dataset, year) {
  periods <- land_price_mappings()$datasets[[dataset]]$shapefile_fields
  matched <- Filter(function(period) {
    year >= period$from && year <= period$to
  }, periods)
  if (length(matched) != 1L) {
    stop("Unsupported Shapefile year: ", dataset, " ", year, call. = FALSE)
  }
  period <- matched[[1L]]
  c(
    admin = period$admin,
    index = period$index,
    sequence = period$sequence,
    price = period$price
  )
}

pad_official_code <- function(value, width) {
  value <- trimws(as.character(value))
  numeric_value <- suppressWarnings(as.integer(value))
  ifelse(
    !is.na(numeric_value),
    sprintf(paste0("%0", width, "d"), numeric_value),
    value
  )
}

land_price_key <- function(dataset, year, admin, index, sequence) {
  paste(
    dataset,
    year,
    pad_official_code(admin, 5L),
    pad_official_code(index, 3L),
    pad_official_code(sequence, 3L),
    sep = ":"
  )
}

check_land_price_shapefile <- function(parsed, shapefile, dataset, year) {
  shape <- suppressWarnings(sf::st_read(
    shapefile,
    options = "ENCODING=CP932",
    quiet = TRUE,
    stringsAsFactors = FALSE
  ))
  mapping <- land_price_shapefile_mapping(dataset, year)
  missing_columns <- setdiff(unname(mapping), names(shape))
  if (length(missing_columns) > 0L) {
    stop(
      "Shapefile columns missing for ",
      dataset,
      " ",
      year,
      ": ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }
  if (nrow(shape) != nrow(parsed$observations)) {
    stop(
      "Shapefile row count differs for ",
      dataset,
      " ",
      year,
      call. = FALSE
    )
  }

  shape_keys <- land_price_key(
    dataset,
    year,
    shape[[mapping[["admin"]]]],
    shape[[mapping[["index"]]]],
    shape[[mapping[["sequence"]]]]
  )
  xml_keys <- land_price_key(
    dataset,
    year,
    parsed$observations$administrative_area_code,
    parsed$observations$point_index_number,
    parsed$observations$point_sequence_number
  )
  if (!identical(sort(shape_keys), sort(xml_keys))) {
    stop(
      "Shapefile point identifiers differ for ",
      dataset,
      " ",
      year,
      call. = FALSE
    )
  }

  shape_prices <- as.numeric(shape[[mapping[["price"]]]])
  xml_prices <- parsed$observations$price_yen_per_m2
  shape_price_signature <- paste(shape_keys, shape_prices, sep = ":")
  xml_price_signature <- paste(xml_keys, xml_prices, sep = ":")
  if (!identical(sort(shape_price_signature), sort(xml_price_signature))) {
    stop(
      "Shapefile prices differ for ",
      dataset,
      " ",
      year,
      call. = FALSE
    )
  }

  expected_crs <- land_price_source_crs(dataset, year)
  if (is.na(sf::st_crs(shape))) {
    sf::st_crs(shape) <- expected_crs
  } else if (!isTRUE(sf::st_crs(shape)$epsg == expected_crs)) {
    stop(
      "Unexpected Shapefile CRS for ",
      dataset,
      " ",
      year,
      call. = FALSE
    )
  }
  shape <- sf::st_transform(shape, 6668)
  shape_coordinates <- sf::st_coordinates(shape)
  xml_coordinates <- sf::st_coordinates(parsed$observations)
  shape_order <- order(
    shape_price_signature,
    shape_coordinates[, "X"],
    shape_coordinates[, "Y"]
  )
  xml_order <- order(
    xml_price_signature,
    xml_coordinates[, "X"],
    xml_coordinates[, "Y"]
  )
  coordinate_difference <- max(abs(
    shape_coordinates[shape_order, , drop = FALSE] -
      xml_coordinates[xml_order, , drop = FALSE]
  ))
  if (!is.finite(coordinate_difference) || coordinate_difference > 1e-7) {
    stop(
      "Shapefile coordinates differ for ",
      dataset,
      " ",
      year,
      call. = FALSE
    )
  }

  list(status = "passed", maximum_coordinate_difference = coordinate_difference)
}

validate_land_price_rows <- function(observations, expected_years) {
  required <- c(
    "observation_id",
    "source_dataset",
    "source_year",
    "administrative_area_code",
    "point_index_number",
    "point_sequence_number",
    "price_yen_per_m2"
  )
  missing_columns <- setdiff(required, names(observations))
  if (length(missing_columns) > 0L) {
    stop(
      "Required observation columns missing: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }
  missing_required <- vapply(required, function(column) {
    values <- observations[[column]]
    any(is.na(values) | (is.character(values) & !nzchar(values)))
  }, logical(1))
  if (any(missing_required)) {
    stop(
      "Required observation values missing in: ",
      paste(required[missing_required], collapse = ", "),
      call. = FALSE
    )
  }
  if (anyDuplicated(observations$observation_id)) {
    stop("Duplicate observation identifiers found.", call. = FALSE)
  }
  if (any(observations$price_yen_per_m2 <= 0)) {
    stop("Land prices must be positive.", call. = FALSE)
  }
  if (!setequal(observations$source_year, expected_years)) {
    stop("Processed observations do not cover the expected years.", call. = FALSE)
  }
  if (any(sf::st_is_empty(observations)) || any(!sf::st_is_valid(observations))) {
    stop("Invalid or empty point geometry found.", call. = FALSE)
  }
  coordinates <- sf::st_coordinates(observations)
  if (
    any(coordinates[, "X"] < 120 | coordinates[, "X"] > 155) ||
      any(coordinates[, "Y"] < 20 | coordinates[, "Y"] > 50)
  ) {
    stop("Point coordinates fall outside the Japan validation bounds.", call. = FALSE)
  }
  invisible(observations)
}

land_price_quality_row <- function(parsed, shapefile_check) {
  observations <- parsed$observations
  coordinates <- sf::st_coordinates(observations)
  data.frame(
    source_dataset = unique(observations$source_dataset),
    source_year = unique(observations$source_year),
    observation_count = nrow(observations),
    supplemental_attribute_count = nrow(parsed$attributes),
    missing_location_count = sum(is.na(observations$location)),
    missing_area_count = sum(is.na(observations$area_m2)),
    minimum_price_yen_per_m2 = min(observations$price_yen_per_m2),
    maximum_price_yen_per_m2 = max(observations$price_yen_per_m2),
    minimum_longitude = min(coordinates[, "X"]),
    maximum_longitude = max(coordinates[, "X"]),
    minimum_latitude = min(coordinates[, "Y"]),
    maximum_latitude = max(coordinates[, "Y"]),
    shapefile_check_status = shapefile_check$status,
    maximum_coordinate_difference = shapefile_check$maximum_coordinate_difference,
    stringsAsFactors = FALSE
  )
}

land_price_output_paths <- function(output_dir, dataset) {
  stats::setNames(
    file.path(output_dir, c(
      paste0(dataset, ".gpkg"),
      paste0(dataset, "_observations.csv"),
      paste0(dataset, "_attributes.csv"),
      paste0(dataset, "_source_metadata.csv"),
      paste0(dataset, "_quality.csv")
    )),
    c(
      "geopackage",
      "observations_csv",
      "attributes_csv",
      "source_metadata_csv",
      "quality_csv"
    )
  )
}

write_land_price_staging <- function(
  staging_dir,
  dataset,
  observations,
  attributes,
  source_metadata,
  quality
) {
  paths <- land_price_output_paths(staging_dir, dataset)
  suppressWarnings(sf::st_write(
    observations,
    paths[["geopackage"]],
    layer = "observations",
    delete_dsn = TRUE,
    quiet = TRUE
  ))
  suppressWarnings(sf::st_write(
    attributes,
    paths[["geopackage"]],
    layer = "attributes",
    append = TRUE,
    quiet = TRUE
  ))
  suppressWarnings(sf::st_write(
    source_metadata,
    paths[["geopackage"]],
    layer = "source_metadata",
    append = TRUE,
    quiet = TRUE
  ))

  coordinates <- sf::st_coordinates(observations)
  observations_csv <- sf::st_drop_geometry(observations)
  observations_csv$longitude <- coordinates[, "X"]
  observations_csv$latitude <- coordinates[, "Y"]
  readr::write_csv(observations_csv, paths[["observations_csv"]], na = "")
  readr::write_csv(attributes, paths[["attributes_csv"]], na = "")
  readr::write_csv(source_metadata, paths[["source_metadata_csv"]], na = "")
  readr::write_csv(quality, paths[["quality_csv"]], na = "")

  layers <- sf::st_layers(paths[["geopackage"]])$name
  expected_layers <- c("observations", "attributes", "source_metadata")
  if (!setequal(layers, expected_layers) || !all(file.exists(paths))) {
    stop("Staged land-price outputs failed validation.", call. = FALSE)
  }
  paths
}

promote_staged_outputs <- function(
  staged_paths,
  final_paths,
  .rename_file = file.rename
) {
  backup_dir <- tempfile(
    pattern = ".land-price-backup-",
    tmpdir = dirname(dirname(final_paths[[1L]]))
  )
  dir.create(backup_dir, recursive = TRUE)
  remove_backup <- TRUE
  on.exit({
    if (remove_backup) {
      unlink(backup_dir, recursive = TRUE, force = TRUE)
    }
  }, add = TRUE)

  existing <- file.exists(final_paths)
  backup_paths <- file.path(backup_dir, basename(final_paths))
  if (any(existing)) {
    moved_to_backup <- .rename_file(
      final_paths[existing],
      backup_paths[existing]
    )
    if (!all(moved_to_backup)) {
      moved_paths <- which(existing)[moved_to_backup]
      restored <- .rename_file(
        backup_paths[moved_paths],
        final_paths[moved_paths]
      )
      if (!all(restored)) {
        remove_backup <- FALSE
        stop(
          "Could not restore processed outputs; backups remain at: ",
          backup_dir,
          call. = FALSE
        )
      }
      stop("Could not stage existing processed outputs for replacement.", call. = FALSE)
    }
  }

  promoted <- .rename_file(staged_paths, final_paths)
  if (!all(promoted)) {
    file.remove(final_paths[promoted])
    if (any(existing)) {
      restored <- .rename_file(backup_paths[existing], final_paths[existing])
      if (!all(restored)) {
        remove_backup <- FALSE
        stop(
          "Could not restore processed outputs; backups remain at: ",
          backup_dir,
          call. = FALSE
        )
      }
    }
    stop("Could not atomically promote processed outputs.", call. = FALSE)
  }
  invisible(final_paths)
}

process_land_price_dataset <- function(
  raw_dir,
  output_dir,
  dataset,
  expected_years = land_price_known_years(dataset)
) {
  expected_years <- as.integer(expected_years)
  if (!all(expected_years %in% land_price_known_years(dataset))) {
    stop("The requested years include an unsupported schema year.", call. = FALSE)
  }

  xml_files <- discover_land_price_files(raw_dir, dataset, "xml")
  shapefiles <- discover_land_price_files(raw_dir, dataset, "shp")
  validate_expected_years(xml_files, expected_years, dataset, "XML")
  validate_expected_years(shapefiles, expected_years, dataset, "Shapefile")

  parsed <- lapply(xml_files, parse_land_price_xml, dataset = dataset)
  names(parsed) <- names(xml_files)
  shape_checks <- lapply(names(parsed), function(year) {
    check_land_price_shapefile(
      parsed[[year]],
      shapefiles[[year]],
      dataset,
      as.integer(year)
    )
  })
  names(shape_checks) <- names(parsed)

  observations <- do.call(rbind, lapply(parsed, `[[`, "observations"))
  attributes <- do.call(rbind, lapply(parsed, `[[`, "attributes"))
  source_metadata <- do.call(rbind, lapply(parsed, `[[`, "source_metadata"))
  quality <- do.call(rbind, lapply(names(parsed), function(year) {
    land_price_quality_row(parsed[[year]], shape_checks[[year]])
  }))
  rownames(observations) <- NULL
  rownames(attributes) <- NULL
  rownames(source_metadata) <- NULL
  rownames(quality) <- NULL
  validate_land_price_rows(observations, expected_years)

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  staging_dir <- tempfile(
    pattern = paste0(".", dataset, "-staging-"),
    tmpdir = dirname(output_dir)
  )
  dir.create(staging_dir, recursive = TRUE)
  on.exit(unlink(staging_dir, recursive = TRUE, force = TRUE), add = TRUE)
  staged_paths <- write_land_price_staging(
    staging_dir,
    dataset,
    observations,
    attributes,
    source_metadata,
    quality
  )
  final_paths <- land_price_output_paths(output_dir, dataset)
  promote_staged_outputs(staged_paths, final_paths)
  final_paths
}

read_brt_stop_history <- function(file) {
  required_columns <- c(
    "stop_id", "stop_name", "xml_name", "start_date", "end_date",
    "phase", "current", "confidence"
  )
  history <- readr::read_csv(
    file,
    col_types = readr::cols(
      .default = readr::col_character(),
      current = readr::col_logical()
    ),
    show_col_types = FALSE
  )
  missing_columns <- setdiff(required_columns, names(history))
  if (length(missing_columns) > 0L) {
    stop(
      "BRT stop history is missing columns: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }
  history <- history[, required_columns]
  if (
    any(is.na(history$stop_id) | !nzchar(history$stop_id)) ||
      anyDuplicated(history$stop_id)
  ) {
    stop("BRT stop_id values must be present and unique.", call. = FALSE)
  }
  if (
    any(is.na(history$xml_name) | !nzchar(history$xml_name)) ||
      anyDuplicated(history$xml_name)
  ) {
    stop("BRT xml_name values must be present and unique.", call. = FALSE)
  }

  start_date_raw <- history$start_date
  end_date_raw <- history$end_date
  history$start_date <- as.Date(start_date_raw)
  history$end_date <- as.Date(end_date_raw)
  invalid_start <- !is.na(start_date_raw) & nzchar(start_date_raw) &
    is.na(history$start_date)
  invalid_end <- !is.na(end_date_raw) & nzchar(end_date_raw) &
    is.na(history$end_date)
  if (
    any(invalid_start) || any(invalid_end) || any(is.na(history$start_date)) ||
      any(!is.na(history$end_date) & history$end_date < history$start_date)
  ) {
    stop("BRT stop history contains invalid dates.", call. = FALSE)
  }
  if (any(is.na(history$current))) {
    stop("BRT stop history contains missing current values.", call. = FALSE)
  }
  history$phase1_initial <- history$start_date == as.Date("2013-03-25") &
    history$phase %in% c("phase1", "historical_phase1")
  as.data.frame(history, stringsAsFactors = FALSE)
}

read_brt_coordinate_validation <- function(file) {
  required_columns <- c(
    "stop_id", "validation_date", "validation_source", "validation_method",
    "validated_by", "latitude", "longitude", "note"
  )
  validation <- readr::read_csv(
    file,
    col_types = readr::cols(
      .default = readr::col_character(),
      latitude = readr::col_double(),
      longitude = readr::col_double()
    ),
    show_col_types = FALSE
  )
  missing_columns <- setdiff(required_columns, names(validation))
  if (length(missing_columns) > 0L) {
    stop(
      "BRT coordinate validation is missing columns: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }
  validation <- validation[, required_columns]
  if (
    any(is.na(validation$stop_id) | !nzchar(validation$stop_id)) ||
      anyDuplicated(validation$stop_id)
  ) {
    stop("Validated BRT stop_id values must be present and unique.", call. = FALSE)
  }
  provenance_columns <- c(
    "validation_source", "validation_method", "validated_by"
  )
  missing_provenance <- vapply(provenance_columns, function(column) {
    values <- validation[[column]]
    any(is.na(values) | !nzchar(trimws(values)))
  }, logical(1))
  if (any(missing_provenance)) {
    stop(
      "BRT coordinate validation source and method must be recorded.",
      call. = FALSE
    )
  }
  validation_date_raw <- validation$validation_date
  validation$validation_date <- as.Date(validation_date_raw)
  invalid_date <- !is.na(validation_date_raw) & nzchar(validation_date_raw) &
    is.na(validation$validation_date)
  if (any(invalid_date) || any(is.na(validation$validation_date))) {
    stop("BRT coordinate validation contains invalid dates.", call. = FALSE)
  }
  if (
    any(!is.finite(validation$latitude)) ||
      any(!is.finite(validation$longitude)) ||
      any(validation$longitude < 120 | validation$longitude > 155) ||
      any(validation$latitude < 20 | validation$latitude > 50)
  ) {
    stop("Validated BRT coordinates fall outside Japan.", call. = FALSE)
  }
  as.data.frame(validation, stringsAsFactors = FALSE)
}

brt_point_index <- function(document) {
  nodes <- xml2::xml_find_all(document, "//*")
  nodes <- nodes[vapply(nodes, xml_local_name, character(1)) == "Point"]
  ids <- vapply(nodes, xml_first_attribute_ending, character(1), suffix = "id")
  if (any(is.na(ids) | !nzchar(ids)) || anyDuplicated(ids)) {
    stop("BRT source Point IDs must be present and unique.", call. = FALSE)
  }
  stats::setNames(as.list(nodes), ids)
}

brt_point_coordinate <- function(point) {
  positions <- xml_direct_children_named(point, "pos")
  values <- xml_nonempty_text(positions)
  if (length(values) != 1L) {
    stop("A BRT source Point must have exactly one coordinate.", call. = FALSE)
  }
  parts <- strsplit(values[[1L]], "[[:space:],]+")[[1L]]
  parts <- parts[nzchar(parts)]
  if (length(parts) != 2L) {
    stop("Expected a BRT latitude/longitude coordinate pair.", call. = FALSE)
  }
  coordinate <- as.numeric(parts)
  if (any(!is.finite(coordinate))) {
    stop("A BRT source Point has a non-numeric coordinate.", call. = FALSE)
  }
  c(latitude = coordinate[[1L]], longitude = coordinate[[2L]])
}

validate_brt_source_crs <- function(document) {
  all_nodes <- xml2::xml_find_all(document, "//*")
  envelopes <- all_nodes[
    vapply(all_nodes, xml_local_name, character(1)) %in%
      c("Envelope", "EnvelopeWithTimePeriod")
  ]
  source_crs <- unique(xml2::xml_attr(envelopes, "srsName"))
  source_crs <- source_crs[!is.na(source_crs) & nzchar(source_crs)]
  expected <- "JGD2011 / (B, L)"
  if (length(source_crs) != 1L || !identical(source_crs, expected)) {
    stop(
      "BRT source XML must declare JGD2011 with latitude/longitude axis order.",
      call. = FALSE
    )
  }
  invisible(expected)
}

parse_brt_stop_xml <- function(file, history) {
  document <- xml2::read_xml(file)
  validate_brt_source_crs(document)
  all_nodes <- xml2::xml_find_all(document, "//*")
  features <- all_nodes[
    vapply(all_nodes, xml_local_name, character(1)) == "BusStop"
  ]
  source_names <- vapply(features, function(feature) {
    xml_first_direct_text(feature, "bsn")
  }, character(1))
  points <- brt_point_index(document)

  rows <- lapply(history$xml_name, function(xml_name) {
    matches <- which(!is.na(source_names) & source_names == xml_name)
    if (length(matches) != 1L) {
      stop(
        "BRT xml_name must match exactly one source feature: ",
        xml_name,
        " (matched ",
        length(matches),
        ")",
        call. = FALSE
      )
    }
    feature <- features[[matches[[1L]]]]
    location <- xml_direct_children_named(feature, "loc")
    if (length(location) != 1L) {
      stop("A BRT source feature must have exactly one Point reference.", call. = FALSE)
    }
    point_id <- xml_first_attribute_ending(location[[1L]], "href")
    point_id <- sub("^#", "", point_id)
    if (is.na(point_id) || !nzchar(point_id) || !point_id %in% names(points)) {
      stop("A BRT source Point reference could not be resolved.", call. = FALSE)
    }
    coordinate <- brt_point_coordinate(points[[point_id]])
    operators <- unique(xml_all_direct_text(feature, "boc"))
    data.frame(
      source_feature_id = xml_first_attribute_ending(feature, "id"),
      source_point_id = point_id,
      source_operator = if (length(operators) == 0L) {
        NA_character_
      } else {
        paste(operators, collapse = " | ")
      },
      longitude = unname(coordinate[["longitude"]]),
      latitude = unname(coordinate[["latitude"]]),
      stringsAsFactors = FALSE
    )
  })
  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result
}

haversine_distance_m <- function(latitude_1, longitude_1, latitude_2, longitude_2) {
  radians <- pi / 180
  latitude_delta <- (latitude_2 - latitude_1) * radians
  longitude_delta <- (longitude_2 - longitude_1) * radians
  value <- sin(latitude_delta / 2)^2 +
    cos(latitude_1 * radians) * cos(latitude_2 * radians) *
      sin(longitude_delta / 2)^2
  6371000 * 2 * atan2(sqrt(value), sqrt(1 - value))
}

attach_brt_validation <- function(stops, validation) {
  unknown_ids <- setdiff(validation$stop_id, stops$stop_id)
  if (length(unknown_ids) > 0L) {
    stop(
      "Coordinate validation refers to unknown BRT stop_id values: ",
      paste(unknown_ids, collapse = ", "),
      call. = FALSE
    )
  }
  validation_index <- match(stops$stop_id, validation$stop_id)
  has_validation <- !is.na(validation_index)
  matched <- validation[validation_index, , drop = FALSE]

  stops$coordinate_source <- paste0(
    "national_land_numerical_information_bus_stops_2022"
  )
  stops$historical_validation_status <- ifelse(
    has_validation,
    "user_verified",
    ifelse(
      stops$phase1_initial,
      "provisional",
      "not_required_for_phase1_analysis"
    )
  )
  stops$historical_validation_method <- matched$validation_method
  stops$historical_validation_source <- matched$validation_source
  stops$historical_validation_date <- matched$validation_date
  stops$historical_validation_by <- matched$validated_by
  stops$validation_latitude <- matched$latitude
  stops$validation_longitude <- matched$longitude
  stops$validation_note <- matched$note
  coordinates <- sf::st_coordinates(stops)
  stops$validation_distance_m <- haversine_distance_m(
    coordinates[, "Y"],
    coordinates[, "X"],
    stops$validation_latitude,
    stops$validation_longitude
  )
  stops
}

validate_brt_stops <- function(
  stops,
  expected_stop_count,
  expected_phase1_initial_count,
  expected_current_count
) {
  if (nrow(stops) != expected_stop_count) {
    stop("Unexpected BRT stop count.", call. = FALSE)
  }
  if (anyDuplicated(stops$stop_id) || anyDuplicated(stops$source_feature_id)) {
    stop("Processed BRT stop identifiers must be unique.", call. = FALSE)
  }
  if (sum(stops$phase1_initial) != expected_phase1_initial_count) {
    stop("Unexpected initial Phase I BRT stop count.", call. = FALSE)
  }
  if (sum(stops$current) != expected_current_count) {
    stop("Unexpected current BRT stop count.", call. = FALSE)
  }
  historical_phase1 <- stops$phase1_initial &
    stops$phase == "historical_phase1"
  if (any(
    stops$historical_validation_status[historical_phase1] != "user_verified"
  )) {
    stop("Historical Phase I BRT stops require coordinate validation.", call. = FALSE)
  }
  if (
    sf::st_crs(stops)$epsg != 6668L || any(sf::st_is_empty(stops)) ||
      any(!sf::st_is_valid(stops))
  ) {
    stop("Processed BRT stop geometry is invalid.", call. = FALSE)
  }
  coordinates <- sf::st_coordinates(stops)
  if (
    any(coordinates[, "X"] < 120 | coordinates[, "X"] > 155) ||
      any(coordinates[, "Y"] < 20 | coordinates[, "Y"] > 50)
  ) {
    stop("Processed BRT coordinates fall outside Japan.", call. = FALSE)
  }
  invisible(stops)
}

brt_duplicate_coord_groups <- function(stops) {
  coordinates <- sf::st_coordinates(stops)
  keys <- paste(
    format(coordinates[, "X"], digits = 15, trim = TRUE),
    format(coordinates[, "Y"], digits = 15, trim = TRUE),
    sep = ":"
  )
  sum(table(keys) > 1L)
}

brt_stop_quality_row <- function(stops) {
  coordinates <- sf::st_coordinates(stops)
  validation_distance <- stops$validation_distance_m
  data.frame(
    source_dataset = "national_land_numerical_information_bus_stops",
    source_year = 2022L,
    source_crs = "JGD2011 / (B, L)",
    status = "passed",
    stop_count = nrow(stops),
    matched_stop_count = sum(!is.na(stops$source_feature_id)),
    current_stop_count = sum(stops$current),
    phase1_initial_count = sum(stops$phase1_initial),
    user_verified_count = sum(
      stops$historical_validation_status == "user_verified"
    ),
    provisional_count = sum(
      stops$historical_validation_status == "provisional"
    ),
    not_required_count = sum(
      stops$historical_validation_status ==
        "not_required_for_phase1_analysis"
    ),
    duplicate_coordinate_group_count = brt_duplicate_coord_groups(
      stops
    ),
    minimum_longitude = min(coordinates[, "X"]),
    maximum_longitude = max(coordinates[, "X"]),
    minimum_latitude = min(coordinates[, "Y"]),
    maximum_latitude = max(coordinates[, "Y"]),
    maximum_validation_distance_m = if (all(is.na(validation_distance))) {
      NA_real_
    } else {
      max(validation_distance, na.rm = TRUE)
    },
    stringsAsFactors = FALSE
  )
}

brt_stop_output_paths <- function(output_dir) {
  stats::setNames(
    file.path(output_dir, c(
      "brt_stops.gpkg",
      "brt_stops.csv",
      "brt_stops_quality.csv"
    )),
    c("geopackage", "stops_csv", "quality_csv")
  )
}

write_brt_stop_staging <- function(staging_dir, stops, quality) {
  paths <- brt_stop_output_paths(staging_dir)
  suppressWarnings(sf::st_write(
    stops,
    paths[["geopackage"]],
    layer = "stops",
    delete_dsn = TRUE,
    quiet = TRUE
  ))
  coordinates <- sf::st_coordinates(stops)
  stops_csv <- sf::st_drop_geometry(stops)
  stops_csv$longitude <- coordinates[, "X"]
  stops_csv$latitude <- coordinates[, "Y"]
  readr::write_csv(stops_csv, paths[["stops_csv"]], na = "")
  readr::write_csv(quality, paths[["quality_csv"]], na = "")

  layers <- sf::st_layers(paths[["geopackage"]])$name
  if (!identical(layers, "stops") || !all(file.exists(paths))) {
    stop("Staged BRT stop outputs failed validation.", call. = FALSE)
  }
  paths
}

process_brt_stops <- function(
  history_file,
  xml_file,
  validation_file,
  output_dir,
  expected_stop_count = 42L,
  expected_phase1_initial_count = 11L,
  expected_current_count = 25L
) {
  history <- read_brt_stop_history(history_file)
  source_rows <- parse_brt_stop_xml(xml_file, history)
  stops <- cbind(history, source_rows)
  stops$source_dataset <- "national_land_numerical_information_bus_stops"
  stops$source_year <- 2022L
  stops <- sf::st_as_sf(
    stops,
    coords = c("longitude", "latitude"),
    crs = 6668,
    remove = TRUE
  )
  validation <- read_brt_coordinate_validation(validation_file)
  stops <- attach_brt_validation(stops, validation)
  validate_brt_stops(
    stops,
    expected_stop_count,
    expected_phase1_initial_count,
    expected_current_count
  )
  quality <- brt_stop_quality_row(stops)

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  staging_dir <- tempfile(
    pattern = ".brt-stops-staging-",
    tmpdir = dirname(output_dir)
  )
  dir.create(staging_dir, recursive = TRUE)
  on.exit(unlink(staging_dir, recursive = TRUE, force = TRUE), add = TRUE)
  staged_paths <- write_brt_stop_staging(staging_dir, stops, quality)
  final_paths <- brt_stop_output_paths(output_dir)
  promote_staged_outputs(staged_paths, final_paths)
  final_paths
}

cluster_land_price_points <- function(
  land_prices,
  tolerance_m = 10,
  metric_crs = 6677
) {
  if (!inherits(land_prices, "sf")) {
    stop("Land-price observations must be an sf object.", call. = FALSE)
  }
  if (!is.numeric(tolerance_m) || length(tolerance_m) != 1L ||
        is.na(tolerance_m) || tolerance_m <= 0) {
    stop("Point matching tolerance must be positive.", call. = FALSE)
  }

  metric <- sf::st_transform(land_prices, metric_crs)
  nearby <- sf::st_is_within_distance(metric, dist = tolerance_m)
  edges <- do.call(
    rbind,
    lapply(seq_along(nearby), function(i) {
      neighbours <- nearby[[i]]
      neighbours <- neighbours[neighbours != i]
      if (length(neighbours) == 0L) {
        return(NULL)
      }
      cbind(i, neighbours)
    })
  )

  graph <- igraph::make_empty_graph(n = nrow(metric), directed = FALSE)
  if (!is.null(edges)) {
    graph <- igraph::add_edges(graph, as.vector(t(edges)))
  }
  land_prices$point_id <- unname(igraph::components(graph)$membership)

  coordinates <- sf::st_coordinates(metric)
  point_locations <- data.frame(
    point_id = land_prices$point_id,
    x = coordinates[, "X"],
    y = coordinates[, "Y"]
  ) |>
    dplyr::group_by(.data$point_id) |>
    dplyr::summarise(
      x = stats::median(.data$x),
      y = stats::median(.data$y),
      observation_count = dplyr::n(),
      .groups = "drop"
    ) |>
    sf::st_as_sf(coords = c("x", "y"), crs = metric_crs)

  representative_coordinates <- sf::st_coordinates(point_locations)
  representative_lookup <- representative_coordinates[
    match(land_prices$point_id, point_locations$point_id),
    ,
    drop = FALSE
  ]
  displacement <- sqrt(rowSums(
    (coordinates - representative_lookup)^2
  ))
  maximum_displacement <- data.frame(
    point_id = land_prices$point_id,
    displacement_m = displacement
  ) |>
    dplyr::group_by(.data$point_id) |>
    dplyr::summarise(
      maximum_displacement_m = max(.data$displacement_m),
      .groups = "drop"
    )
  point_locations <- dplyr::left_join(
    point_locations,
    maximum_displacement,
    by = "point_id"
  )

  point_year_counts <- sf::st_drop_geometry(land_prices) |>
    dplyr::count(.data$point_id, .data$source_year, name = "n")

  list(
    observations = land_prices,
    points = point_locations,
    duplicate_point_year_count = sum(point_year_counts$n > 1L)
  )
}

prepare_land_price_analysis_data <- function( # nolint: object_length_linter.
  observations,
  point_match_tolerance_m = 10,
  metric_crs = 6677
) {
  required_columns <- c(
    "observation_id",
    "source_dataset",
    "source_year"
  )
  if (!all(required_columns %in% names(observations))) {
    stop("Land-price observations are missing analysis columns.", call. = FALSE)
  }
  if (nrow(observations) == 0L) {
    stop("Land-price observations must not be empty.", call. = FALSE)
  }
  if (anyNA(observations$observation_id) ||
        anyDuplicated(observations$observation_id)) {
    stop("Land-price observation IDs must be complete and unique.", call. = FALSE)
  }

  source_datasets <- unique(observations$source_dataset)
  source_datasets <- source_datasets[!is.na(source_datasets)]
  if (length(source_datasets) != 1L || anyNA(observations$source_dataset)) {
    stop(
      "Land-price analysis data must contain exactly one source dataset.",
      call. = FALSE
    )
  }

  clustered <- cluster_land_price_points(
    observations,
    tolerance_m = point_match_tolerance_m,
    metric_crs = metric_crs
  )
  cluster_id_map <- sf::st_drop_geometry(clustered$observations) |>
    dplyr::group_by(.data$point_id) |>
    dplyr::summarise(
      minimum_observation_id = min(.data$observation_id),
      .groups = "drop"
    ) |>
    dplyr::arrange(.data$minimum_observation_id) |>
    dplyr::mutate(
      stable_point_id = sprintf(
        "%s_%05d",
        source_datasets[[1L]],
        dplyr::row_number()
      )
    )

  observations_with_points <- clustered$observations
  observations_with_points$point_id <- cluster_id_map$stable_point_id[
    match(observations_with_points$point_id, cluster_id_map$point_id)
  ]
  point_year_counts <- observations_with_points |>
    sf::st_drop_geometry() |>
    dplyr::count(.data$point_id, .data$source_year, name = "point_year_observation_count")
  point_year_panel <- observations_with_points |>
    dplyr::left_join(
      point_year_counts,
      by = c("point_id", "source_year")
    ) |>
    dplyr::mutate(
      duplicate_point_year = .data$point_year_observation_count > 1L
    )

  point_summaries <- point_year_panel |>
    sf::st_drop_geometry() |>
    dplyr::group_by(.data$point_id) |>
    dplyr::summarise(
      observation_count = dplyr::n(),
      first_source_year = min(.data$source_year),
      last_source_year = max(.data$source_year),
      observed_year_count = dplyr::n_distinct(.data$source_year),
      duplicate_point_year_count = sum(
        !duplicated(.data$source_year) & .data$duplicate_point_year
      ),
      .groups = "drop"
    )
  point_registry <- clustered$points
  point_registry$point_id <- cluster_id_map$stable_point_id[
    match(point_registry$point_id, cluster_id_map$point_id)
  ]
  point_registry <- point_registry |>
    dplyr::select("point_id", "maximum_displacement_m") |>
    dplyr::left_join(point_summaries, by = "point_id") |>
    dplyr::arrange(.data$point_id)

  quality <- data.frame(
    point_match_tolerance_m = point_match_tolerance_m,
    clustered_point_count = nrow(point_registry),
    duplicate_point_year_count = sum(point_year_counts$point_year_observation_count > 1L),
    maximum_cluster_displacement_m = max(
      point_registry$maximum_displacement_m
    ),
    stringsAsFactors = FALSE
  )

  list(
    point_year_panel = point_year_panel,
    point_registry = point_registry,
    quality = quality
  )
}

calculate_point_stop_distances <- function(
  point_registry,
  stops,
  metric_crs = 6677
) {
  if (!inherits(point_registry, "sf") || !inherits(stops, "sf")) {
    stop("Point registry and BRT stops must be sf objects.", call. = FALSE)
  }
  if (!"point_id" %in% names(point_registry) ||
        !"stop_id" %in% names(stops)) {
    stop("Point registry or BRT stops are missing ID columns.", call. = FALSE)
  }
  if (nrow(point_registry) == 0L || nrow(stops) == 0L) {
    stop("Point registry and BRT stops must not be empty.", call. = FALSE)
  }
  if (anyNA(point_registry$point_id) || anyDuplicated(point_registry$point_id) ||
        anyNA(stops$stop_id) || anyDuplicated(stops$stop_id)) {
    stop("Point and stop IDs must be complete and unique.", call. = FALSE)
  }

  point_metric <- sf::st_transform(point_registry, metric_crs)
  stop_metric <- sf::st_transform(stops, metric_crs)
  distance_matrix <- sf::st_distance(point_metric, stop_metric)

  tidyr::expand_grid(
    point_id = point_registry$point_id,
    stop_id = stops$stop_id
  ) |>
    dplyr::mutate(
      distance_m = as.numeric(t(distance_matrix))
    )
}

filter_complete_point_panel <- function(point_year_panel, years) {
  required_columns <- c("point_id", "source_year")
  if (!all(required_columns %in% names(point_year_panel))) {
    stop("Point-year panel is missing panel columns.", call. = FALSE)
  }
  years <- sort(unique(as.integer(years)))
  if (length(years) == 0L || anyNA(years)) {
    stop("Panel years must contain at least one non-missing year.", call. = FALSE)
  }

  point_year_counts <- point_year_panel |>
    sf::st_drop_geometry() |>
    dplyr::filter(.data$source_year %in% years) |>
    dplyr::count(.data$point_id, .data$source_year, name = "n")
  complete_ids <- point_year_counts |>
    dplyr::group_by(.data$point_id) |>
    dplyr::summarise(
      observed_year_count = dplyr::n_distinct(.data$source_year),
      one_observation_per_year = all(.data$n == 1L),
      .groups = "drop"
    ) |>
    dplyr::filter(
      .data$observed_year_count == length(years),
      .data$one_observation_per_year
    ) |>
    dplyr::pull(.data$point_id)

  point_year_panel |>
    dplyr::filter(
      .data$point_id %in% complete_ids,
      .data$source_year %in% years
    ) |>
    dplyr::arrange(.data$point_id, .data$source_year)
}

assign_brt_stop_within_radius <- function(
  point_stop_distances,
  stops,
  stop_radius_m,
  eligible_stop_ids = stops$stop_id
) {
  distance_columns <- c("point_id", "stop_id", "distance_m")
  stop_columns <- c("stop_id", "start_date")
  if (!all(distance_columns %in% names(point_stop_distances)) ||
        !all(stop_columns %in% names(stops))) {
    stop("BRT distance or stop data are missing assignment columns.", call. = FALSE)
  }
  if (!is.numeric(stop_radius_m) || length(stop_radius_m) != 1L ||
        is.na(stop_radius_m) || stop_radius_m <= 0) {
    stop("Stop radius must be positive.", call. = FALSE)
  }
  if (length(eligible_stop_ids) == 0L || anyNA(eligible_stop_ids)) {
    stop("Eligible BRT stop IDs must be non-empty and complete.", call. = FALSE)
  }
  if (anyDuplicated(stops$stop_id) || anyNA(stops$stop_id)) {
    stop("BRT stop IDs must be complete and unique.", call. = FALSE)
  }
  unknown_stop_ids <- setdiff(eligible_stop_ids, stops$stop_id)
  if (length(unknown_stop_ids) > 0L) {
    stop("Eligible BRT stop IDs are not present in the stop data.", call. = FALSE)
  }

  stop_openings <- stops |>
    sf::st_drop_geometry() |>
    dplyr::transmute(
      stop_id = .data$stop_id,
      opening_date = as.Date(.data$start_date)
    )
  selected <- point_stop_distances |>
    dplyr::filter(
      .data$stop_id %in% eligible_stop_ids,
      !is.na(.data$distance_m),
      .data$distance_m <= stop_radius_m
    ) |>
    dplyr::left_join(stop_openings, by = "stop_id") |>
    dplyr::filter(!is.na(.data$opening_date)) |>
    dplyr::arrange(
      .data$point_id,
      .data$opening_date,
      .data$distance_m,
      .data$stop_id
    ) |>
    dplyr::group_by(.data$point_id) |>
    dplyr::slice_head(n = 1L) |>
    dplyr::ungroup() |>
    dplyr::select("point_id", "stop_id", "opening_date", "distance_m")

  point_stop_distances |>
    dplyr::distinct(.data$point_id) |>
    dplyr::arrange(.data$point_id) |>
    dplyr::left_join(selected, by = "point_id") |>
    dplyr::mutate(
      within_stop_radius = !is.na(.data$stop_id),
      .after = "point_id"
    ) |>
    dplyr::select(
      "point_id",
      "within_stop_radius",
      "stop_id",
      "opening_date",
      "distance_m"
    )
}

derive_brt_proximity_panel <- function(
  point_year_panel,
  point_stop_distances,
  stops,
  stop_radius_m,
  service_interruptions = NULL
) {
  panel_columns <- c("point_id", "reference_date")
  distance_columns <- c("point_id", "stop_id", "distance_m")
  stop_columns <- c(
    "stop_id",
    "start_date",
    "end_date",
    "confidence",
    "historical_validation_status"
  )
  if (!all(panel_columns %in% names(point_year_panel)) ||
        !all(distance_columns %in% names(point_stop_distances)) ||
        !all(stop_columns %in% names(stops))) {
    stop("BRT stop proximity inputs are missing required columns.", call. = FALSE)
  }
  if (!is.numeric(stop_radius_m) || length(stop_radius_m) != 1L ||
        is.na(stop_radius_m) || stop_radius_m <= 0) {
    stop("Stop radius must be positive.", call. = FALSE)
  }
  if (anyNA(stops$stop_id) || anyDuplicated(stops$stop_id)) {
    stop("BRT stop IDs must be complete and unique.", call. = FALSE)
  }

  panel_keys <- point_year_panel |>
    sf::st_drop_geometry() |>
    dplyr::distinct(.data$point_id, .data$reference_date) |>
    dplyr::mutate(reference_date = as.Date(.data$reference_date))
  stop_periods <- stops |>
    sf::st_drop_geometry() |>
    dplyr::transmute(
      stop_id = as.character(.data$stop_id),
      start_date = as.Date(.data$start_date),
      end_date = as.Date(.data$end_date),
      confidence = as.character(.data$confidence),
      historical_validation_status = as.character(
        .data$historical_validation_status
      )
    )
  if (anyNA(panel_keys$point_id) || anyNA(panel_keys$reference_date) ||
        anyNA(stop_periods$start_date)) {
    stop("BRT stop proximity IDs and dates must be complete.", call. = FALSE)
  }

  if (is.null(service_interruptions)) {
    service_interruptions <- data.frame(
      stop_id = character(),
      inactive_start_date = as.Date(character()),
      inactive_end_date = as.Date(character())
    )
  }
  interruption_columns <- c(
    "stop_id",
    "inactive_start_date",
    "inactive_end_date"
  )
  if (!all(interruption_columns %in% names(service_interruptions))) {
    stop("BRT service interruptions are missing required columns.", call. = FALSE)
  }
  service_interruptions <- service_interruptions |>
    dplyr::transmute(
      stop_id = as.character(.data$stop_id),
      inactive_start_date = as.Date(.data$inactive_start_date),
      inactive_end_date = as.Date(.data$inactive_end_date)
    )
  if (nrow(service_interruptions) > 0L &&
        (anyNA(service_interruptions) ||
           any(service_interruptions$inactive_start_date >
                 service_interruptions$inactive_end_date) ||
           any(!service_interruptions$stop_id %in% stop_periods$stop_id))) {
    stop("BRT service interruption periods are invalid.", call. = FALSE)
  }

  candidates <- panel_keys |>
    dplyr::inner_join(
      point_stop_distances,
      by = "point_id",
      relationship = "many-to-many"
    ) |>
    dplyr::inner_join(stop_periods, by = "stop_id") |>
    dplyr::filter(
      !is.na(.data$distance_m),
      .data$reference_date >= .data$start_date,
      is.na(.data$end_date) | .data$reference_date <= .data$end_date
    )
  if (nrow(service_interruptions) > 0L) {
    candidates <- candidates |>
      dplyr::left_join(
        service_interruptions,
        by = "stop_id",
        relationship = "many-to-many"
      ) |>
      dplyr::mutate(
        interrupted = !is.na(.data$inactive_start_date) &
          .data$reference_date >= .data$inactive_start_date &
          .data$reference_date <= .data$inactive_end_date
      ) |>
      dplyr::group_by(
        .data$point_id,
        .data$reference_date,
        .data$stop_id,
        .data$distance_m,
        .data$confidence,
        .data$historical_validation_status
      ) |>
      dplyr::summarise(
        interrupted = any(.data$interrupted),
        .groups = "drop"
      ) |>
      dplyr::filter(!.data$interrupted)
  }

  active_summary <- candidates |>
    dplyr::arrange(
      .data$point_id,
      .data$reference_date,
      .data$distance_m,
      .data$stop_id
    ) |>
    dplyr::group_by(.data$point_id, .data$reference_date) |>
    dplyr::summarise(
      active_stop_count_within_radius = sum(
        .data$distance_m <= stop_radius_m
      ),
      nearest_active_stop_id = dplyr::first(.data$stop_id),
      nearest_active_stop_distance_m = dplyr::first(.data$distance_m),
      nearest_active_stop_confidence = dplyr::first(.data$confidence),
      nearest_active_stop_historical_validation_status = dplyr::first(
        .data$historical_validation_status
      ),
      active_stop_proximity_has_non_high_confidence = any(
        .data$distance_m <= stop_radius_m &
          (is.na(.data$confidence) | .data$confidence != "high")
      ),
      active_stop_proximity_uses_unvalidated_historical_location = any(
        .data$distance_m <= stop_radius_m &
          (is.na(.data$historical_validation_status) |
             .data$historical_validation_status != "user_verified")
      ),
      .groups = "drop"
    )

  treatment_panel <- point_year_panel |>
    dplyr::left_join(active_summary, by = c("point_id", "reference_date")) |>
    dplyr::mutate(
      active_stop_count_within_radius = dplyr::coalesce(
        .data$active_stop_count_within_radius,
        0L
      ),
      active_stop_proximity_has_non_high_confidence = dplyr::coalesce(
        .data$active_stop_proximity_has_non_high_confidence,
        FALSE
      ),
      active_stop_proximity_uses_unvalidated_historical_location =
        dplyr::coalesce(
          .data$active_stop_proximity_uses_unvalidated_historical_location,
          FALSE
        ),
      within_active_stop_radius = .data$active_stop_count_within_radius > 0L,
      .after = "reference_date"
    )

  treatment_panel
}

append_brt_proximity_events <- function(
  treatment_panel,
  point_stop_distances,
  stops,
  stop_radius_m,
  service_interruptions,
  service_events
) {
  event_columns <- c("event_id", "event_date", "service_period")
  if (!all(event_columns %in% names(service_events))) {
    stop("BRT service events are missing required columns.", call. = FALSE)
  }
  service_events <- service_events |>
    dplyr::transmute(
      event_id = as.character(.data$event_id),
      event_date = as.Date(.data$event_date),
      service_period = as.character(.data$service_period)
    ) |>
    dplyr::arrange(.data$event_date)
  if (nrow(service_events) == 0L || anyNA(service_events) ||
        anyDuplicated(service_events$event_id) ||
        anyDuplicated(service_events$event_date) ||
        any(!grepl("^[A-Za-z0-9_]+$", service_events$event_id))) {
    stop("BRT service events must be complete, unique, and safely named.", call. = FALSE)
  }

  period_index <- findInterval(
    as.numeric(as.Date(treatment_panel$reference_date)),
    as.numeric(service_events$event_date)
  )
  treatment_panel$service_period <- c(
    "pre_brt",
    service_events$service_period
  )[period_index + 1L]

  event_panel <- tidyr::expand_grid(
    point_id = unique(treatment_panel$point_id),
    event_id = service_events$event_id,
    event_state = c("before", "after")
  ) |>
    dplyr::left_join(
      dplyr::select(service_events, "event_id", "event_date"),
      by = "event_id"
    ) |>
    dplyr::mutate(
      reference_date = .data$event_date - as.integer(.data$event_state == "before")
    )
  event_states <- derive_brt_proximity_panel(
    event_panel,
    point_stop_distances,
    stops,
    stop_radius_m = stop_radius_m,
    service_interruptions = service_interruptions
  ) |>
    sf::st_drop_geometry() |>
    dplyr::select(
      "point_id",
      "event_id",
      "event_state",
      "within_active_stop_radius"
    ) |>
    tidyr::pivot_wider(
      names_from = "event_state",
      values_from = "within_active_stop_radius"
    ) |>
    dplyr::mutate(
      active_stop_proximity_gain = !.data$before & .data$after,
      active_stop_proximity_loss = .data$before & !.data$after
    )

  for (event_row in seq_len(nrow(service_events))) {
    event_id <- service_events$event_id[[event_row]]
    event_date <- service_events$event_date[[event_row]]
    gain_column <- paste0("active_stop_proximity_gain_", event_id)
    loss_column <- paste0("active_stop_proximity_loss_", event_id)
    post_column <- paste0("post_", event_id)
    gain_treated_column <- paste0(gain_column, "_treated")
    loss_treated_column <- paste0(loss_column, "_treated")
    event_assignment <- event_states |>
      dplyr::filter(.data$event_id == .env$event_id) |>
      dplyr::select(
        "point_id",
        "active_stop_proximity_gain",
        "active_stop_proximity_loss"
      )
    names(event_assignment)[
      names(event_assignment) == "active_stop_proximity_gain"
    ] <- gain_column
    names(event_assignment)[
      names(event_assignment) == "active_stop_proximity_loss"
    ] <- loss_column
    treatment_panel <- treatment_panel |>
      dplyr::left_join(
        event_assignment,
        by = "point_id",
        relationship = "many-to-one"
      )
    treatment_panel[[post_column]] <-
      as.Date(treatment_panel$reference_date) >= event_date
    treatment_panel[[gain_treated_column]] <-
      treatment_panel[[gain_column]] & treatment_panel[[post_column]]
    treatment_panel[[loss_treated_column]] <-
      treatment_panel[[loss_column]] & treatment_panel[[post_column]]
  }

  treatment_panel
}

derive_brt_treatment_panel <- function(
  point_year_panel,
  point_stop_distances,
  stops,
  stop_radius_m,
  service_interruptions = NULL,
  service_events = NULL
) {
  treatment_panel <- derive_brt_proximity_panel(
    point_year_panel,
    point_stop_distances,
    stops,
    stop_radius_m = stop_radius_m,
    service_interruptions = service_interruptions
  )
  if (is.null(service_events)) {
    return(treatment_panel)
  }

  append_brt_proximity_events(
    treatment_panel,
    point_stop_distances,
    stops,
    stop_radius_m = stop_radius_m,
    service_interruptions = service_interruptions,
    service_events = service_events
  )
}

assert_brt_proximity_monotone <- function(
  treatment_panel,
  proximity_column = "within_active_stop_radius",
  point_column = "point_id",
  date_column = "reference_date",
  source_label = NULL
) {
  required_columns <- c(proximity_column, point_column, date_column)
  if (!all(required_columns %in% names(treatment_panel))) {
    stop("BRT stop proximity input is missing required columns.", call. = FALSE)
  }
  diagnostic <- treatment_panel |>
    sf::st_drop_geometry() |>
    dplyr::transmute(
      point_id = as.character(.data[[point_column]]),
      reference_date = as.Date(.data[[date_column]]),
      proximity_value = .data[[proximity_column]]
    )
  if (anyNA(diagnostic) ||
        any(!diagnostic$proximity_value %in% c(FALSE, TRUE, 0L, 1L)) ||
        anyDuplicated(diagnostic[c("point_id", "reference_date")])) {
    stop(
      "BRT stop proximity input must have one complete binary value per point-date.",
      call. = FALSE
    )
  }
  reversals <- diagnostic |>
    dplyr::mutate(proximity_value = as.logical(.data$proximity_value)) |>
    dplyr::arrange(.data$point_id, .data$reference_date) |>
    dplyr::group_by(.data$point_id) |>
    dplyr::mutate(
      previous_proximity = dplyr::lag(
        .data$proximity_value,
        default = dplyr::first(.data$proximity_value)
      )
    ) |>
    dplyr::ungroup() |>
    dplyr::filter(.data$previous_proximity & !.data$proximity_value)
  if (nrow(reversals) > 0L) {
    source_text <- if (is.null(source_label)) {
      ""
    } else {
      paste0(" for ", source_label)
    }
    shown <- utils::head(reversals, 10L)
    detail <- paste0(
      shown$point_id,
      " at ",
      format(shown$reference_date, "%Y-%m-%d"),
      collapse = "; "
    )
    stop(
      "Active BRT stop proximity monotonicity failed",
      source_text,
      ": ",
      nrow(reversals),
      " treatment reversal(s): ",
      detail,
      call. = FALSE
    )
  }

  treatment_panel
}

build_baseline_covariates <- function(
  point_year_panel,
  baseline_year,
  columns = character()
) {
  required_columns <- c("point_id", "source_year")
  if (!all(required_columns %in% names(point_year_panel))) {
    stop("Point-year panel is missing baseline columns.", call. = FALSE)
  }
  if (!is.numeric(baseline_year) || length(baseline_year) != 1L ||
        is.na(baseline_year) || baseline_year != as.integer(baseline_year)) {
    stop("Baseline year must be one integer year.", call. = FALSE)
  }
  if (anyNA(columns) || anyDuplicated(columns)) {
    stop("Baseline covariate names must be complete and unique.", call. = FALSE)
  }
  protected_columns <- c(
    "point_id",
    "observation_id",
    "source_year",
    "reference_date"
  )
  if (any(columns %in% protected_columns)) {
    stop(
      "Identifier and time columns cannot be used as baseline covariates.",
      call. = FALSE
    )
  }
  unknown_columns <- setdiff(columns, names(point_year_panel))
  if (length(unknown_columns) > 0L) {
    stop("Baseline covariates are not present in the point-year panel.", call. = FALSE)
  }
  geometry_column <- attr(point_year_panel, "sf_column")
  non_spatial_panel <- sf::st_drop_geometry(point_year_panel)
  list_column <- vapply(
    non_spatial_panel[setdiff(columns, geometry_column)],
    is.list,
    logical(1)
  )
  if (any(columns %in% geometry_column) || any(list_column)) {
    stop(
      "geometry or list columns cannot be used as baseline covariates.",
      call. = FALSE
    )
  }

  baseline_rows <- point_year_panel |>
    sf::st_drop_geometry() |>
    dplyr::filter(.data$source_year == as.integer(baseline_year))
  duplicate_points <- baseline_rows |>
    dplyr::count(.data$point_id, name = "n") |>
    dplyr::filter(.data$n > 1L) |>
    dplyr::pull(.data$point_id)
  if (length(duplicate_points) > 0L) {
    stop(
      sprintf(
        "Baseline year has multiple observations for point IDs: %s",
        paste(duplicate_points, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  baseline_rows |>
    dplyr::select(
      "point_id",
      baseline_source_year = "source_year",
      dplyr::all_of(columns)
    ) |>
    dplyr::arrange(.data$point_id)
}
