testthat::test_that("2012 publication XML becomes a standard observation", {
  result <- parse_land_price_xml(
    file = testthat::test_path("..", "fixtures", "land_price", "l01_2012.xml"),
    dataset = "land_price_publication"
  )

  testthat::expect_named(
    result,
    c("observations", "attributes", "source_metadata")
  )
  testthat::expect_s3_class(result$observations, "sf")
  testthat::expect_equal(nrow(result$observations), 1L)
  testthat::expect_equal(result$observations$source_year, 2012L)
  testthat::expect_equal(
    result$observations$observation_id,
    "land_price_publication:2012:08202:005:007:fixture-l01-2012-1"
  )
  testthat::expect_equal(result$observations$price_yen_per_m2, 54321)
  testthat::expect_equal(result$observations$location, "架空町1-2")
  testthat::expect_equal(result$observations$area_m2, 123)
  testthat::expect_equal(sf::st_crs(result$observations)$epsg, 6668L)
  testthat::expect_false("source_crs_epsg" %in% names(result$observations))

  testthat::expect_equal(result$source_metadata$source_crs_epsg, 4612L)
  testthat::expect_equal(result$source_metadata$output_crs_epsg, 6668L)
  testthat::expect_equal(result$source_metadata$source_axis_order, "latitude_longitude")
  testthat::expect_equal(
    result$attributes$attribute_name,
    "historicalValue"
  )
  testthat::expect_equal(result$attributes$raw_value, "999")
})

testthat::test_that("2019 survey GI XML uses the same observation contract", {
  result <- parse_land_price_xml(
    file = testthat::test_path("..", "fixtures", "land_price", "l02_2019.xml"),
    dataset = "prefectural_land_price_survey"
  )

  observation <- result$observations
  testthat::expect_equal(observation$source_year, 2019L)
  testthat::expect_equal(
    observation$observation_id,
    paste0(
      "prefectural_land_price_survey:2019:08202:010:011:",
      "fixture-l02-2019-1"
    )
  )
  testthat::expect_equal(observation$reference_date, as.Date("2019-07-01"))
  testthat::expect_equal(observation$price_yen_per_m2, 45678)
  testthat::expect_equal(observation$area_m2, 456)
  testthat::expect_equal(sf::st_crs(observation)$epsg, 6668L)
  testthat::expect_equal(result$source_metadata$source_crs_epsg, 4612L)
})

testthat::test_that("2013 survey values preserve inference and sentinel status", {
  result <- parse_land_price_xml(
    file = testthat::test_path("..", "fixtures", "land_price", "l02_2013.xml"),
    dataset = "prefectural_land_price_survey"
  )
  observation <- result$observations

  testthat::expect_equal(observation$current_use_raw, "住宅,店舗")
  testthat::expect_equal(observation$current_use_json, '["住宅","店舗"]')
  testthat::expect_equal(observation$current_use_status, "reported")
  testthat::expect_true(is.na(observation$usage_class_coarse))
  testthat::expect_equal(observation$usage_class_status, "unmapped")
  testthat::expect_equal(observation$building_material, "RC")
  testthat::expect_equal(observation$floors_above, 3L)
  testthat::expect_equal(observation$floors_below, 1L)
  testthat::expect_equal(observation$building_parse_status, "parsed_legacy")
  testthat::expect_true(observation$water_available_or_supplied)
  testthat::expect_equal(observation$water_facility_status, "mapped")
  testthat::expect_false(observation$gas_available_or_supplied)
  testthat::expect_equal(observation$gas_facility_status, "mapped")
  testthat::expect_equal(observation$sewage_facility_status, "mapped")
  testthat::expect_equal(observation$shape_mapping_status, "mapped")
  testthat::expect_equal(observation$front_road_class_coarse, "municipal")
  testthat::expect_equal(observation$front_road_class_status, "mapped")
  testthat::expect_equal(observation$front_road_width_m, 4)
  testthat::expect_equal(
    observation$front_road_width_status,
    "inferred_unit_m"
  )
  testthat::expect_true(is.na(observation$transport_distance_m))
  testthat::expect_equal(observation$transport_access_status, "at_station")
  testthat::expect_equal(observation$building_coverage_pct, 60)
  testthat::expect_equal(observation$floor_area_ratio_pct, 200)
  testthat::expect_true(observation$paved)
  testthat::expect_equal(observation$pavement_status, "mapped")
})

testthat::test_that("Japanese road labels normalize under the Windows locale", {
  testthat::expect_equal(normalize_road_class("\u5e02\u9053"), "municipal")
  testthat::expect_equal(normalize_road_class("\u56fd\u9053"), "national")
})

testthat::test_that("a dataset is checked and written through the public seam", {
  root <- withr::local_tempdir()
  raw_dir <- file.path(root, "raw")
  output_dir <- file.path(root, "processed")
  dir.create(raw_dir)
  fixture <- testthat::test_path(
    "..",
    "fixtures",
    "land_price",
    "l01_2012.xml"
  )
  file.copy(fixture, file.path(raw_dir, "L01-12_08.xml"))

  shape <- sf::st_as_sf(
    data.frame(
      L01_017 = "08202",
      L01_001 = "005",
      L01_002 = "007",
      L01_005 = 2012,
      L01_006 = 54321,
      L01_019 = "架空町1-2",
      longitude = 140.5,
      latitude = 36.5,
      stringsAsFactors = FALSE
    ),
    coords = c("longitude", "latitude"),
    crs = 4612
  )
  suppressWarnings(sf::st_write(
    shape,
    file.path(raw_dir, "L01-12_08.shp"),
    quiet = TRUE
  ))

  outputs <- process_land_price_dataset(
    raw_dir = raw_dir,
    output_dir = output_dir,
    dataset = "land_price_publication",
    expected_years = 2012L
  )

  testthat::expect_true(all(file.exists(outputs)))
  testthat::expect_setequal(
    sf::st_layers(outputs[["geopackage"]])$name,
    c("observations", "attributes", "source_metadata")
  )
  csv_observations <- readr::read_csv(
    outputs[["observations_csv"]],
    show_col_types = FALSE
  )
  testthat::expect_equal(nrow(csv_observations), 1L)
  testthat::expect_equal(csv_observations$price_yen_per_m2, 54321)
  quality <- readr::read_csv(outputs[["quality_csv"]], show_col_types = FALSE)
  testthat::expect_equal(quality$shapefile_check_status, "passed")
  testthat::expect_equal(quality$observation_count, 1L)
})

testthat::test_that("the targets pipeline exposes both processed datasets", {
  manifest <- targets::tar_manifest(
    fields = c("name", "format"),
    script = testthat::test_path("..", "..", "_targets.R"),
    callr_function = NULL
  )

  expected <- c(
    "land_price_publication_outputs",
    "prefectural_land_price_survey_outputs"
  )
  testthat::expect_true(all(expected %in% manifest$name))
  testthat::expect_true(all(manifest$format[manifest$name %in% expected] == "file"))
})

testthat::test_that("the machine-readable contract covers processed columns", {
  project_root <- testthat::test_path("..", "..")
  dictionary <- readr::read_csv(
    file.path(project_root, "config", "land_price_columns.csv"),
    show_col_types = FALSE
  )
  parsed <- parse_land_price_xml(
    file = testthat::test_path("..", "fixtures", "land_price", "l02_2013.xml"),
    dataset = "prefectural_land_price_survey"
  )

  observation_columns <- c(names(parsed$observations), "longitude", "latitude")
  testthat::expect_setequal(
    observation_columns,
    dictionary$column_name[dictionary$table == "observations"]
  )
  mappings <- yaml::read_yaml(
    file.path(project_root, "config", "land_price_mappings.yml")
  )
  testthat::expect_equal(
    mappings$datasets$land_price_publication$source_crs[[1]]$epsg,
    4612L
  )
  testthat::expect_equal(
    mappings$exceptions$prefectural_land_price_survey_2013_road_width$status,
    "inferred_unit_m"
  )
})

testthat::test_that("fixtures cover every schema era and known XML exception", {
  cases <- data.frame(
    file = c(
      "l01_2012.xml", "l01_2014.xml", "l01_2018.xml", "l01_2022.xml",
      "l01_2026.xml", "l02_1983.xml", "l02_2013.xml", "l02_2019.xml",
      "l02_2021.xml", "l02_2025.xml"
    ),
    dataset = c(
      rep("land_price_publication", 5),
      rep("prefectural_land_price_survey", 5)
    ),
    year = c(2012, 2014, 2018, 2022, 2026, 1983, 2013, 2019, 2021, 2025),
    stringsAsFactors = FALSE
  )

  parsed <- Map(function(file, dataset, year) {
    result <- parse_land_price_xml(
      testthat::test_path("..", "fixtures", "land_price", file),
      dataset
    )
    testthat::expect_equal(result$observations$source_year, as.integer(year))
    testthat::expect_equal(nrow(result$observations), 1L)
    testthat::expect_false(anyNA(result$observations$observation_id))
    result
  }, cases$file, cases$dataset, cases$year)

  testthat::expect_true(
    "altitudeDistric" %in% parsed[[5]]$attributes$attribute_name
  )
  testthat::expect_true(
    "altitudeDistric" %in% parsed[[10]]$attributes$attribute_name
  )
})

testthat::test_that("a partial backup failure restores every moved output", {
  root <- withr::local_tempdir()
  staging_dir <- file.path(root, "staging")
  final_dir <- file.path(root, "processed")
  dir.create(staging_dir)
  dir.create(final_dir)
  staged <- file.path(staging_dir, c("one.csv", "two.csv"))
  final <- file.path(final_dir, c("one.csv", "two.csv"))
  writeLines("new one", staged[[1L]])
  writeLines("new two", staged[[2L]])
  writeLines("old one", final[[1L]])
  writeLines("old two", final[[2L]])

  rename_call <- 0L
  rename_with_partial_failure <- function(from, to) {
    rename_call <<- rename_call + 1L
    if (rename_call == 1L) {
      first <- base::file.rename(from[[1L]], to[[1L]])
      return(c(first, rep(FALSE, length(from) - 1L)))
    }
    base::file.rename(from, to)
  }

  testthat::expect_error(
    promote_staged_outputs(
      staged,
      final,
      .rename_file = rename_with_partial_failure
    ),
    "Could not stage existing processed outputs"
  )
  restored_contents <- vapply(final, readLines, character(1))
  testthat::expect_equal(unname(restored_contents), c("old one", "old two"))
})
