#!/usr/bin/env Rscript
.bs_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
bs <- Find(file.exists, c(
  if (length(.bs_file)) file.path(dirname(sub("^--file=", "", .bs_file[1])), "bootstrap.R"),
  file.path("scripts", "bootstrap.R"), file.path("..", "..", "scripts", "bootstrap.R")))
if (!length(bs)) stop("bootstrap.R not found")
source(bs[1]); rm(bs, .bs_file)
suppressMessages(library(data.table))
source(.find("ofo_preflight_lib.R"))      # stage records
source(.find("ofo_reference_lib.R"))      # contracts, signals, path guards
source(.find("ofo_registration_lib.R"))   # OFO_REG2 (smallest stem counts)
source(.find("ofo_conditions_lib.R"))     # conditions admission
source(.find("ofo_disturbance_lib.R"))

# Assembles the inputs of the decision stage for the Open Forest Observatory
# second preflight (docs/ofo-preflight-protocol-2.md, "Registering catalogue
# plots", "Disturbance between survey and flight" and "Decision"), groups A
# and B, then runs preflight_ofo_decision.R on them. Score-blind.
#   registration.csv  the first protocol's contract, one row per candidate plot
#                     of groups A and B: registered when the group's signal is
#                     admitted by the crown-frame test (crowntruth_test.json,
#                     top-level `admitted`), the plot's method-2 estimate for
#                     it is accepted by the frozen gate at no fewer than the
#                     smallest stem count, second_peak is at most 0.8 and, in
#                     group A where the diameter estimate is also accepted,
#                     the two estimates lie within 2.0 m; gate columns follow.
#   conditions.csv    the first protocol's contract for the plots of groups A
#                     and B with a cloud: snow and leaf-off copied from the
#                     first protocol, disturbance from disturbance.csv (a
#                     record or canopy failure is evidence; a check not made,
#                     such as presence not_checked, leaves the plot unchecked).
#   registration_tests.json  top-level `admitted` copied from
#                     crowntruth_test.json (the decision reads nothing else),
#                     the crown-frame test itself and the catalogue gates.
# The run stops unless the records of the first-protocol stages and
# disturbance_record.json are current, and unless the canopy check ran
# exactly on the plots these gates register.
# Inputs: OFO/preflight/{plots,flights,registration_catalog,conditions}.csv,
#   registration_tests.json (read-only); OFO/preflight2/{crowntruth_test.json,
#   disturbance.csv}.
# Outputs (P2 = OFO/preflight2): registration.csv, conditions.csv,
#   registration_tests.json, assemble_record.json, then the decision's
#   {cells,plot_admission,group_summary,group_decision}.csv and
#   decision_record.json (preflight_ofo_decision.R IN2=P2 OUT=P2 GROUPS=A,B).
#   Rscript scripts/preflight_ofo2_assemble.R [DECISION=TRUE]
args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
A <- setNames(lapply(args, function(x) paste(x[-1], collapse = "=")), sapply(args, `[`, 1))
unknown <- setdiff(names(A), "DECISION")
if (length(unknown)) stop("Unknown argument(s): ", paste(unknown, collapse = ", "))
DECISION <- isTRUE(as.logical(if (is.null(A$DECISION)) "TRUE" else A$DECISION))

job <- normalizePath(.job_dir(), mustWork = FALSE)
OFO <- file.path(job, "ofo")
PRE <- file.path(OFO, "preflight")
P2 <- file.path(OFO, "preflight2")
for (p in file.path(P2, c("registration.csv", "conditions.csv", "registration_tests.json",
                          "assemble_record.json")))
  if (!ofo_path_under(p, P2) || ofo_path_within(ofo_path_resolve(p),
                                                ofo_path_resolve(file.path(job, "neon"))))
    stop("Refusing to write outside ", P2, ": ", p)

## ---- inputs and their records ----------------------------------------------------
stale <- ofo_check_records(PRE, c(
  flights_record.json = "preflight_ofo_catalog.R STEPS=flights",
  conditions_record.json = "preflight_ofo_conditions.R",
  registration_catalog_record.json = "preflight_ofo_registration.R STAGE=catalog"))
drec_path <- file.path(P2, "disturbance_record.json")
if (!file.exists(drec_path)) {
  stale <- c(stale, "disturbance_record.json is missing: run preflight_ofo_disturbance.R")
} else {
  bad <- ofo_p2_record_mismatch(jsonlite::read_json(drec_path), P2, PRE)
  if (length(bad)) stale <- c(stale, sprintf(
    "disturbance_record.json: %s; rerun preflight_ofo_disturbance.R STAGE=presence",
    paste(bad, collapse = "; ")))
}
if (length(stale)) stop("Inputs are not current:\n  ", paste(stale, collapse = "\n  "),
                        call. = FALSE)
in_pre <- c("plots.csv", "flights.csv", "registration_catalog.csv", "conditions.csv",
            "registration_tests.json")
in_p2 <- c("crowntruth_test.json", "disturbance.csv")
sha_pre <- ofo_sha256(PRE, in_pre); sha_p2 <- ofo_sha256(P2, in_p2)
if (anyNA(c(sha_pre, sha_p2))) stop("Missing input(s): ", paste(c(
  file.path(PRE, in_pre[is.na(sha_pre)]), file.path(P2, in_p2[is.na(sha_p2)])), collapse = ", "))
ct_raw <- jsonlite::read_json(file.path(P2, "crowntruth_test.json"), simplifyVector = FALSE)
ct_js <- jsonlite::read_json(file.path(P2, "crowntruth_test.json"), simplifyVector = TRUE)
admitted <- ofo_signals_admitted(ct_js)
# A test with fewer than 10 units is inconclusive: the signal is not admitted.
# The protocol makes only a failed test no-go and does not say how an
# inconclusive one enters the group rule; this preflight reads it as a check
# that could not be made (see the results document, Decision).
inconclusive <- vapply(c("height", "rank"), function(s)
  isTRUE(ct_js$signals[[s]]$inconclusive), logical(1))
if (any(inconclusive & admitted)) stop("crowntruth_test.json: a signal is both admitted and inconclusive")
p1_tests <- jsonlite::read_json(file.path(PRE, "registration_tests.json"), simplifyVector = TRUE)
rd <- function(dir, f, chr = "plot_id")
  as.data.frame(fread(file.path(dir, f), na.strings = c("", "NA"),
                      colClasses = list(character = chr)))
plots <- ofo_read_input(PRE, "plots.csv")
flights <- rd(PRE, "flights.csv", c("plot_id", "flight_days"))
cat_tab <- rd(PRE, "registration_catalog.csv")
cond1 <- ofo_read_input(PRE, "conditions.csv")
dist <- rd(P2, "disturbance.csv", c("plot_id", "interval_start", "interval_end"))

## ---- registration ------------------------------------------------------------------
reg <- ofo_p2_registration(plots, flights, cat_tab, admitted, inconclusive = inconclusive)
if (!setequal(reg$plot_id, dist$plot_id))
  stop("disturbance.csv covers other plots than the candidates of groups A and B; ",
       "rerun preflight_ofo_disturbance.R")
# The canopy check runs at registered positions: it must have run on exactly
# the plots registered now.
ran <- dist$plot_id[!dist$presence_status %in% "not_run"]
want <- reg$plot_id[reg$registered]
if (!setequal(ran, want))
  stop("The canopy check ran on other plots than those registered (ran: ",
       paste(sort(ran), collapse = ","), "; registered: ", paste(sort(want), collapse = ","),
       "); rerun preflight_ofo_disturbance.R STAGE=presence", call. = FALSE)

## ---- conditions --------------------------------------------------------------------
cond <- ofo_p2_conditions(cond1, dist)

## ---- test record -------------------------------------------------------------------
gate_counts <- lapply(stats::setNames(OFO_DIST_GROUPS, OFO_DIST_GROUPS), function(g) {
  x <- reg[reg$group == g, , drop = FALSE]
  list(candidates = nrow(x), flight_admitted = sum(x$flight_admitted),
       signal_admitted = isTRUE(admitted[[OFO_GROUP_SIGNAL[[g]]]]),
       accepted_frozen_gate = sum(x$flight_admitted & x$accepted & x$at_min_stems),
       one_clear_peak = sum(x$flight_admitted & x$accepted & x$at_min_stems & x$second_peak_ok),
       signals_agree = sum(x$flight_admitted & x$accepted & x$at_min_stems & x$second_peak_ok &
                             x$agreement_ok),
       registered = sum(x$registered))
})
tests <- list(
  status = "protocol 2: crown-frame test and the catalogue gates of groups A and B",
  admitted = as.list(admitted),
  inconclusive = as.list(inconclusive),
  protocol2 = list(
    protocol = "docs/ofo-preflight-protocol-2.md",
    admitted_from = "crowntruth_test.json, top-level `admitted`",
    crowntruth_test_sha256 = sha_p2[["crowntruth_test.json"]],
    crowntruth_test = ct_raw,
    catalog_gates = list(
      rule = paste("registered: the group's signal admitted; its method-2 estimate accepted",
                   "by the frozen gate at no fewer than the smallest stem count; second_peak",
                   "at most 0.8; in group A, where the diameter estimate is also accepted,",
                   "the height and diameter estimates within 2.0 m; an admitted flight"),
      second_peak_max = OFO_P2_GATES$second_peak_max,
      agreement_max_m = OFO_P2_GATES$agreement_max_m,
      method_digest_sha256 = ofo2_config_digest(),
      smallest_stem_count = list(height = OFO_REG2$height$gate$min_stems,
                                 rank = OFO_REG2$rank$gate$min_stems),
      by_group = gate_counts)),
  protocol1 = list(registration_tests_sha256 = sha_pre[["registration_tests.json"]],
                   admitted = p1_tests$admitted))
if (!identical(ofo2_config_digest(),
               "eede36eb4afc37a385dc3b204f0dcf660c29cc60bcf893293c8a546bb54803b6"))
  stop("The method-2 constants differ from the frozen digest of Amendment 1b")

## ---- outputs -----------------------------------------------------------------------
fwrite(reg, file.path(P2, "registration.csv"))
fwrite(cond, file.path(P2, "conditions.csv"))
jsonlite::write_json(tests, file.path(P2, "registration_tests.json"), auto_unbox = TRUE,
                     pretty = TRUE, digits = NA, na = "null", null = "null")
if (!identical(ofo_sha256(PRE, in_pre), sha_pre) || !identical(ofo_sha256(P2, in_p2), sha_p2))
  stop("Inputs changed during the run; rerun preflight_ofo2_assemble.R", call. = FALSE)
ofo_write_record(ofo_p2_record("protocol2 assemble", P2, sha_p2,
                               c("registration.csv", "conditions.csv", "registration_tests.json"),
                               PRE, sha_pre, list(signals_admitted = as.list(admitted))),
                 file.path(P2, "assemble_record.json"))

cat(sprintf("signals admitted (crown-frame test): height %s, rank %s\n", admitted[["height"]],
            admitted[["rank"]]))
cat("\ncandidate plots of groups A and B:\n")
print(reg[, c("plot_id", "group", "signal_used", "n_signal", "flight_admitted", "accepted",
              "second_peak", "agreement_m", "registered", "reason")], row.names = FALSE,
      digits = 3)
cat("\nconditions (plots with a cloud):\n")
print(table(disturbance = cond$disturbance_status, admitted = cond$conditions_admitted))
cat(sprintf(paste("\nwrote %s/{registration,conditions}.csv, registration_tests.json,",
                  "assemble_record.json\n"), P2))

## ---- decision ----------------------------------------------------------------------
if (DECISION) {
  rscript <- file.path(R.home("bin"), "Rscript")
  st <- system2(rscript, c(.find("preflight_ofo_decision.R"), paste0("IN2=", P2),
                           paste0("OUT=", P2), "GROUPS=A,B"),
                env = paste0("CLAUDE_JOB_DIR=", job))
  if (!identical(as.integer(st), 0L)) stop("preflight_ofo_decision.R failed (status ", st, ")")
}
