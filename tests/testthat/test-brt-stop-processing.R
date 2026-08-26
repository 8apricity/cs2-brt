brt_fixture_path <- function(file) {
  testthat::test_path("..", "fixtures", "brt_stops", file)
}

testthat::test_that("managed BRT stop files become analysis-ready outputs", {
  output_dir <- withr::local_tempdir()

  outputs <- process_brt_stops(
    history_file = brt_fixture_path("brt_stop_history.csv"),
    xml_file = brt_fixture_path("p11_2022.xml"),
    validation_file = brt_fixture_path(
      "brt_stop_coordinate_validation.csv"
    ),
    output_dir = output_dir,
    expected_stop_count = 3L,
    expected_phase1_initial_count = 2L,
    expected_current_count = 2L
  )

  testthat::expect_true(all(file.exists(outputs)))
  testthat::expect_named(
    outputs,
    c("geopackage", "stops_csv", "quality_csv")
  )
  testthat::expect_setequal(
    sf::st_layers(outputs[["geopackage"]])$name,
    "stops"
  )

  stops <- readr::read_csv(outputs[["stops_csv"]], show_col_types = FALSE)
  testthat::expect_equal(nrow(stops), 3L)
  testthat::expect_equal(sum(stops$phase1_initial), 2L)
  testthat::expect_equal(
    stops$historical_validation_status[stops$stop_id == "H1"],
    "user_verified"
  )
  testthat::expect_equal(
    stops$historical_validation_status[stops$stop_id == "1"],
    "provisional"
  )
  testthat::expect_equal(
    stops$historical_validation_status[stops$stop_id == "2"],
    "not_required_for_phase1_analysis"
  )

  quality <- readr::read_csv(
    outputs[["quality_csv"]],
    show_col_types = FALSE
  )
  testthat::expect_equal(quality$status, "passed")
  testthat::expect_equal(quality$stop_count, 3L)
  testthat::expect_equal(quality$phase1_initial_count, 2L)
})

testthat::test_that("the targets pipeline exposes BRT stop processing", {
  manifest <- targets::tar_manifest(
    fields = c("name", "format"),
    script = testthat::test_path("..", "..", "_targets.R"),
    callr_function = NULL
  )

  expected_file_targets <- c(
    "brt_stop_history_file",
    "brt_stop_coordinate_validation_file",
    "brt_stop_2022_xml_file",
    "brt_stop_outputs"
  )
  testthat::expect_true(all(expected_file_targets %in% manifest$name))
  testthat::expect_true(all(
    manifest$format[manifest$name %in% expected_file_targets] == "file"
  ))
})

testthat::test_that("coordinate validation requires reproducible provenance", {
  root <- withr::local_tempdir()
  validation <- readr::read_csv(
    brt_fixture_path("brt_stop_coordinate_validation.csv"),
    show_col_types = FALSE
  )
  validation$validation_source <- NA_character_
  validation_file <- file.path(root, "validation.csv")
  readr::write_csv(validation, validation_file, na = "")

  testthat::expect_error(
    process_brt_stops(
      history_file = brt_fixture_path("brt_stop_history.csv"),
      xml_file = brt_fixture_path("p11_2022.xml"),
      validation_file = validation_file,
      output_dir = file.path(root, "processed"),
      expected_stop_count = 3L,
      expected_phase1_initial_count = 2L,
      expected_current_count = 2L
    ),
    "validation source and method"
  )
})

testthat::test_that("source matching failures stop BRT processing", {
  root <- withr::local_tempdir()

  unmatched_history <- readr::read_csv(
    brt_fixture_path("brt_stop_history.csv"),
    show_col_types = FALSE
  )
  unmatched_history$xml_name[[1L]] <- "存在しない停留所"
  unmatched_file <- file.path(root, "unmatched-history.csv")
  readr::write_csv(unmatched_history, unmatched_file, na = "")
  testthat::expect_error(
    process_brt_stops(
      history_file = unmatched_file,
      xml_file = brt_fixture_path("p11_2022.xml"),
      validation_file = brt_fixture_path(
        "brt_stop_coordinate_validation.csv"
      ),
      output_dir = file.path(root, "unmatched"),
      expected_stop_count = 3L,
      expected_phase1_initial_count = 2L,
      expected_current_count = 2L
    ),
    "matched 0"
  )

  source_xml <- readr::read_file(brt_fixture_path("p11_2022.xml"))
  duplicate_feature <- paste0(
    "  <ksj:BusStop gml:id=\"bs4\">\n",
    "    <ksj:loc xlink:href=\"#n1\"/>\n",
    "    <ksj:bsn>第Ⅰ期現存</ksj:bsn>\n",
    "    <ksj:boc>架空バス株式会社</ksj:boc>\n",
    "  </ksj:BusStop>\n"
  )
  duplicate_xml <- sub(
    "</ksj:Dataset>",
    paste0(duplicate_feature, "</ksj:Dataset>"),
    source_xml,
    fixed = TRUE
  )
  duplicate_file <- file.path(root, "duplicate.xml")
  readr::write_file(duplicate_xml, duplicate_file)
  testthat::expect_error(
    process_brt_stops(
      history_file = brt_fixture_path("brt_stop_history.csv"),
      xml_file = duplicate_file,
      validation_file = brt_fixture_path(
        "brt_stop_coordinate_validation.csv"
      ),
      output_dir = file.path(root, "duplicate"),
      expected_stop_count = 3L,
      expected_phase1_initial_count = 2L,
      expected_current_count = 2L
    ),
    "matched 2"
  )

  broken_reference_xml <- sub(
    "xlink:href=\"#n1\"",
    "xlink:href=\"#missing\"",
    source_xml,
    fixed = TRUE
  )
  broken_reference_file <- file.path(root, "broken-reference.xml")
  readr::write_file(broken_reference_xml, broken_reference_file)
  testthat::expect_error(
    process_brt_stops(
      history_file = brt_fixture_path("brt_stop_history.csv"),
      xml_file = broken_reference_file,
      validation_file = brt_fixture_path(
        "brt_stop_coordinate_validation.csv"
      ),
      output_dir = file.path(root, "broken-reference"),
      expected_stop_count = 3L,
      expected_phase1_initial_count = 2L,
      expected_current_count = 2L
    ),
    "could not be resolved"
  )
})

testthat::test_that("BRT stop counts are hard quality gates", {
  root <- withr::local_tempdir()
  testthat::expect_error(
    process_brt_stops(
      history_file = brt_fixture_path("brt_stop_history.csv"),
      xml_file = brt_fixture_path("p11_2022.xml"),
      validation_file = brt_fixture_path(
        "brt_stop_coordinate_validation.csv"
      ),
      output_dir = root,
      expected_stop_count = 4L,
      expected_phase1_initial_count = 2L,
      expected_current_count = 2L
    ),
    "Unexpected BRT stop count"
  )
})

testthat::test_that("duplicate coordinates are reported without failing", {
  root <- withr::local_tempdir()
  source_xml <- readr::read_file(brt_fixture_path("p11_2022.xml"))
  duplicate_coordinate_xml <- sub(
    "36.52000000 140.62000000",
    "36.50000000 140.60000000",
    source_xml,
    fixed = TRUE
  )
  xml_file <- file.path(root, "duplicate-coordinate.xml")
  readr::write_file(duplicate_coordinate_xml, xml_file)

  outputs <- process_brt_stops(
    history_file = brt_fixture_path("brt_stop_history.csv"),
    xml_file = xml_file,
    validation_file = brt_fixture_path(
      "brt_stop_coordinate_validation.csv"
    ),
    output_dir = file.path(root, "processed"),
    expected_stop_count = 3L,
    expected_phase1_initial_count = 2L,
    expected_current_count = 2L
  )
  quality <- readr::read_csv(
    outputs[["quality_csv"]],
    show_col_types = FALSE
  )
  testthat::expect_equal(quality$duplicate_coordinate_group_count, 1L)
})
