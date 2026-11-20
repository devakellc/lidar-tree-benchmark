# Unit tests for the pure helpers of reference_population_audit.R: NEON bole
# identities, crown-class provenance, fire windows and their timing against
# reference dates and flights, status transitions across a fire, fire keys
# across perimeter sources, date conversion and query URLs. Synthetic input
# only; nothing is read from disk or the network.
env <- new.env(parent = globalenv())
source(file.path("..", "..", "scripts", "reference_population_audit.R"), local = env)
for (f in ls(env)) assign(f, get(f, envir = env))

test_that("a trailing capital letter marks an additional bole of the base individual", {
  id <- c("NEON.PLA.D17.SJER.00064A", "NEON.PLA.D17.SJER.00064", "NEON.PLA.D16.WREF.04424AB",
          "NEON.PLA.D17.SOAP.03098C", "local-tag-7", NA)
  b <- ra_bole_parse(id)
  expect_equal(b$base_id[1:2], rep("NEON.PLA.D17.SJER.00064", 2))
  expect_equal(b$bole_suffix, c("A", "", "", "C", "", ""))
  expect_equal(b$additional_bole, c(TRUE, FALSE, FALSE, TRUE, FALSE, FALSE))
  expect_equal(b$standard_id, c(TRUE, TRUE, FALSE, TRUE, FALSE, FALSE))
  expect_equal(b$base_id[3], id[3])                   # two letters: not a NEON bole ID
  expect_equal(b$base_id[4], "NEON.PLA.D17.SOAP.03098")
})

test_that("bole families are counted within a site", {
  site <- c("S", "S", "S", "S", "T")
  id <- c("NEON.PLA.D17.SJER.00064", "NEON.PLA.D17.SJER.00064A", "NEON.PLA.D17.SJER.00064B",
          "NEON.PLA.D17.SJER.00070", "NEON.PLA.D17.SJER.00064A")
  f <- ra_bole_families(site, id)
  expect_equal(f$records_of_individual, c(3, 3, 3, 1, 1))
  expect_equal(f$multi_bole_individual, c(TRUE, TRUE, TRUE, FALSE, TRUE))
  expect_equal(sum(f$additional_bole), 3)
  expect_equal(length(unique(paste(site, f$base_id))), 3)
})

test_that("crown-class source follows the canopy-position map, then the height fallback", {
  cp <- c("Open grown", "Full sun", "Partially shaded", "Mostly shaded", "Full shade", NA, NA, NA,
          "Not recorded")
  cc <- c("dominant", "dominant", "codominant", "intermediate", "suppressed", "codominant", NA, "",
          "suppressed")
  expect_equal(ra_crown_source(cp, cc),
               c(rep("canopy_position", 5), "height_fallback", "none", "none", "height_fallback"))
  expect_error(ra_crown_source("Full sun", "suppressed"), "disagrees")
  expect_error(ra_crown_source("Full shade", NA), "disagrees")
})

test_that("fire windows run from alarm to containment, else to year end or the whole year", {
  w <- ra_fire_window(as.Date(c("2020-09-04", "2021-06-29", NA)), as.Date(c("2020-12-24", NA, NA)),
                      c(2020, 2021, 2017))
  expect_equal(w$fire_start, as.Date(c("2020-09-04", "2021-06-29", "2017-01-01")))
  expect_equal(w$fire_end, as.Date(c("2020-12-24", "2021-12-31", "2017-12-31")))
  expect_equal(w$window_basis, c("alarm to containment", "alarm to year end", "fire year only"))
  expect_error(ra_fire_window(as.Date("2020-09-04"), as.Date("2020-09-01"), 2020), "precedes")
  expect_error(ra_fire_window(as.Date(NA), as.Date(NA), NA), "alarm date or a fire year")
})

test_that("window relations use the whole fire window", {
  expect_equal(ra_relation(as.Date("2020-09-04"), as.Date("2020-12-24"),
                           as.Date(c("2021-07-12", "2018-06-01", "2020-12-24")),
                           as.Date(c("2021-07-13", "2018-06-30", "2021-01-10"))),
               c("before", "after", "overlaps"))
})

test_that("references measured before a fire that preceded the flight are flagged", {
  fl <- as.Date(c("2021-07-12", "2021-07-13")); sp <- as.Date(c("2018-06-01", "2018-06-30"))
  fs <- as.Date("2020-09-04"); fe <- as.Date("2020-12-24")
  x <- ra_classify_fire(fs, fe, as.Date(rep("2019-06-10", 3)), fl[1], fl[2], sp[1], sp[2])
  expect_equal(x$reading, "references_predate_fire_before_flight")
  expect_equal(c(x$ref_before_fire, x$ref_during_fire, x$ref_after_fire), c(3, 0, 0))
  expect_equal(x$fire_vs_flight_2021, "before")
  expect_equal(x$fire_vs_sparse_flight, "after")
  expect_true(x$between_sparse_and_2021)
  y <- ra_classify_fire(fs, fe, as.Date(c("2021-12-22", "2023-09-07")), fl[1], fl[2], sp[1], sp[2])
  expect_equal(y$reading, "remeasured_after_fire_before_flight")
  expect_equal(y$fire_vs_reference, "references_postdate_fire")
  z <- ra_classify_fire(fs, fe, as.Date(c("2019-06-10", "2020-10-01", "2023-09-07")), fl[1], fl[2])
  expect_equal(z$reading, "references_span_fire_before_flight")
  expect_equal(c(z$ref_before_fire, z$ref_during_fire, z$ref_after_fire), c(1, 1, 1))
  expect_true(is.na(z$fire_vs_sparse_flight)); expect_true(is.na(z$between_sparse_and_2021))
})

test_that("fires after the flight, or during it, are told apart", {
  fl <- as.Date(c("2021-07-13", "2021-07-14")); sp <- as.Date(c("2018-06-01", "2018-06-30"))
  g <- ra_classify_fire(as.Date("2025-08-24"), as.Date("2025-10-23"), as.Date("2021-08-10"),
                        fl[1], fl[2], sp[1], sp[2])
  expect_equal(g$reading, "fire_after_flight_and_references")
  expect_equal(g$fire_vs_sparse_flight, "after"); expect_false(g$between_sparse_and_2021)
  h <- ra_classify_fire(as.Date("2022-08-01"), as.Date("2022-09-01"), as.Date("2023-07-01"), fl[1], fl[2])
  expect_equal(h$reading, "fire_after_flight_references_after_fire")
  d <- ra_classify_fire(as.Date("2021-07-10"), as.Date("2021-07-13"), as.Date("2019-06-01"), fl[1], fl[2])
  expect_equal(d$reading, "fire_during_flight")
  e <- ra_classify_fire(as.Date("2016-07-01"), as.Date("2016-08-01"), as.Date("2019-06-01"),
                        fl[1], fl[2], sp[1], sp[2])
  expect_equal(e$fire_vs_sparse_flight, "before"); expect_false(e$between_sparse_and_2021)
  expect_error(ra_classify_fire(as.Date("2020-09-04"), as.Date("2020-12-24"), as.Date(character()),
                                fl[1], fl[2]), "Reference dates")
})

test_that("status transitions pair the last pre-fire and first post-fire record", {
  ai <- data.frame(
    plotID = c("P1", "P1", "P1", "P1", "P1", "P1", "P1", "P1", "P1", "P1", "P2", "P2"),
    individualID = c("A", "A", "B", "B", "B", "C", "D", "D", "D", "E", "F", "F"),
    date = c("2015-06-01", "2023-09-07", "2015-06-01", "2019-06-01", "2023-09-07", "2019-06-01",
             "2015-06-01", "2021-12-22", "2023-09-07", "2019-06-01", "2015-06-01", "2023-09-07"),
    plantStatus = c("Live", "Standing dead", "Live", "Standing dead", "Downed", "Live", "Live",
                    "Live, physically damaged", "Standing dead", "Live", "Live", "Standing dead"),
    stemDiameter = c(30, 30, 12, 12, NA, 15, 8, 9, 9, 20, 40, 40), stringsAsFactors = FALSE)
  ai <- rbind(ai, data.frame(plotID = "P1", individualID = "E", date = "2019-06-01",
                             plantStatus = "Standing dead", stemDiameter = 20))
  ai <- rbind(ai, data.frame(plotID = "P1", individualID = "E", date = "2023-09-07",
                             plantStatus = "Downed", stemDiameter = NA))
  tr <- ra_status_transitions(ai, "P1", as.Date("2020-09-04"))
  expect_equal(tr$individualID, c("A", "B", "D", "E"))     # C has no post-fire record; F is in P2
  expect_equal(tr$pre_status, c("Live", "Standing dead", "Live", "Standing dead"))  # E: last row of the day
  expect_equal(tr$post_status, c("Standing dead", "Downed", "Live, physically damaged", "Downed"))
  expect_equal(tr$pre_live, c(TRUE, FALSE, TRUE, FALSE))
  expect_equal(tr$post_live, c(FALSE, FALSE, TRUE, FALSE))
  expect_equal(tr$pre_date, as.Date(c("2015-06-01", "2019-06-01", "2015-06-01", "2019-06-01")))
  expect_equal(tr$post_date, as.Date(c("2023-09-07", "2023-09-07", "2021-12-22", "2023-09-07")))
  expect_equal(tr$pre_dbh, c(30, 12, 8, 20))
})

test_that("fire keys join copies by IRWIN ID, then by a unique name and year", {
  k <- ra_fire_keys(c("CREEK", "Creek", "CREEK", "BLUE", "GARNET", "Garnet", "GARNET"),
                    c(2020, 2020, 2020, 2021, 2025, 2025, 2025),
                    c("{33cbb9dc-6983}", "33CBB9DC-6983", NA, NA, "AAA", "BBB", NA))
  expect_equal(k[1:3], rep("IRWIN:33CBB9DC-6983", 3))
  expect_equal(k[4], "NAME:BLUE|2021")
  expect_equal(k[5:6], c("IRWIN:AAA", "IRWIN:BBB"))
  expect_equal(k[7], "NAME:GARNET|2025")                   # two IRWIN candidates: left alone
  expect_equal(ra_irwin(c(" {ab-1} ", "", NA)), c("AB-1", NA, NA))
})

test_that("ArcGIS dates keep CAL FIRE's UTC date and WFIGS's local date", {
  expect_equal(ra_ms_date_utc(1599177600000), as.Date("2020-09-04"))
  late <- as.numeric(as.POSIXct("2020-09-05 03:00:00", tz = "UTC")) * 1000
  expect_equal(ra_ms_date_local(late), as.Date("2020-09-04"))       # 20:00 PDT on 4 September
  expect_equal(ra_ms_date_utc(as.POSIXct("2020-12-24", tz = "UTC")), as.Date("2020-12-24"))
  expect_true(is.na(ra_ms_date_utc(NA)))
})

test_that("fire remarks match fire, burning and scorch but not firewood", {
  expect_equal(ra_fire_remark(c("Fire; Bole scorch", "firewood stack", NA, "Burnt", "charred base", NA),
                              c("Live", "Live", "Lost, burned", NA, "Live", "Live")),
               c(TRUE, FALSE, TRUE, TRUE, TRUE, FALSE))
})

test_that("query URLs are percent-encoded", {
  expect_equal(ra_query_url("https://example.org/FeatureServer/0", list(where = "YEAR_ >= 2015", f = "json")),
               "https://example.org/FeatureServer/0/query?where=YEAR_%20%3E%3D%202015&f=json")
  expect_equal(ra_where(RA_SOURCES$nifc_wfigs, c(2015, 2025)),
               paste("(attr_FireDiscoveryDateTime >= DATE '2015-01-01' AND",
                     "attr_FireDiscoveryDateTime < DATE '2026-01-01') OR attr_FireDiscoveryDateTime IS NULL"))
  expect_equal(ra_where(RA_SOURCES$calfire_frap, c(2015, 2025)), "YEAR_ >= 2015 AND YEAR_ <= 2025")
})
