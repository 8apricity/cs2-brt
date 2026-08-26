stops <- sf::st_read(here::here("data", "processed", "brt_stops.gpkg"))
land_price_publication <- sf::st_read(here::here("data", "processed", "land_price_publication.gpkg"), layer = "observations")
prefectural_land_price_survey <- sf::st_read(here::here("data", "processed", "prefectural_land_price_survey.gpkg"), layer = "observations")

dist_threshold <- 10

near <- sf::st_is_within_distance(
  land_price_publication,
  dist = dist_threshold
)

edges <- do.call(
  rbind,
  lapply(seq_along(near), function(i) {
    j <- near[[i]]
    j <- j[j != i]  # 自分自身を除外

    if (length(j) == 0) return(NULL)

    cbind(i, j)
  })
)

g <- igraph::make_empty_graph(n = nrow(land_price_publication), directed = FALSE)

if (!is.null(edges)) {
  g <- igraph::add_edges(g, t(edges))
}

land_price_publication$point_id <- igraph::components(g)$membership
