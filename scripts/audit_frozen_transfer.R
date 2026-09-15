#!/usr/bin/env Rscript
# Bounded training-only inference and diagnostics; see the predeclared protocol.
source("scripts/detect_external_fgiemit.R")

audit_infer <- function(root, plots, python) {
  opt <- fgi_options(c("SPLIT=training", paste0("PLOTS=", paste(plots, collapse = ",")),
    "ARMS=forestformer3d,treeisonet", paste0("DATA_DIR=", root, "/source"),
    paste0("OUT_DIR=", root, "/audit/corrected"), paste0("EVAL_PYTHON=", python)))
  res <- fgi_resources(opt)
  provenance <- fgi_provenance(opt, res)
  extra <- c(.find("audit_frozen_transfer.R"), file.path(.ROOT, "gpu/export_treeisonet_audit.py"),
             file.path(.ROOT, "docs/frozen-transfer-audit-runtime-note.md"))
  provenance$audit_files <- as.list(tools::md5sum(extra))
  prepared <- c(file.path(root, "training/prepared/1001", c("raw.laz", "normalized.laz")),
                file.path(root, "audit/baseline_1019/prepared/1019", c("raw.laz", "normalized.laz")))
  if (any(!file.exists(prepared))) stop("Frozen preparation for both declared plots must finish first")
  provenance$prepared_md5 <- as.list(tools::md5sum(prepared))
  dir.create(opt$out, recursive = TRUE, showWarnings = FALSE)
  manifest <- file.path(opt$out, "run_manifest.rds")
  if (!fgi_manifest(manifest, provenance)) {
    saveRDS(provenance, manifest)
    jsonlite::write_json(provenance, file.path(opt$out, "run_manifest.json"), auto_unbox = TRUE, pretty = TRUE)
  }
  for (pid in plots) {
    baseline <- if (pid == "1001") file.path(root, "training") else file.path(root, "audit/baseline_1019")
    prep <- as.list(setNames(file.path(baseline, "prepared", pid,
                                      c("raw.laz", "normalized.laz", "classical.laz")),
                             c("raw", "normalized", "classical")))
    if (any(!file.exists(unlist(prep)))) stop("Frozen plot preparation must finish first")
    for (arm in opt$arms) {
      directory <- file.path(opt$out, "runs", pid, arm)
      receipt <- file.path(directory, "receipt.rds")
      if (file.exists(receipt)) {
        old <- readRDS(receipt)
        if (!identical(old, tools::md5sum(names(old)))) stop("Audit output changed: ", directory)
        next
      }
      archive <- file.path(directory, "forward.npz")
      if (arm == "treeisonet") Sys.setenv(TREEISONET_AUDIT_OUT = archive)
      t0 <- Sys.time()
      result <- tryCatch(fgi_run_arm(arm, prep, directory, opt, res, provenance$images),
                         finally = Sys.unsetenv("TREEISONET_AUDIT_OUT"))
      if (is.null(result)) stop("Audit inference failed: ", pid, "/", arm)
      outputs <- file.path(directory, if (arm == "treeisonet") "aligned.laz" else "predictions.laz")
      if (arm == "treeisonet") {
        ablations <- file.path(directory, "ablations.laz")
        code <- system2(python, shQuote(c(file.path(.ROOT, "gpu/export_treeisonet_audit.py"),
                                         prep$normalized, archive, ablations)))
        if (code != 0L) stop("Cannot export aligned diagnostic labels")
        outputs <- c(outputs, archive, ablations, paste0(ablations, ".json"))
      } else outputs <- c(outputs, paste0(outputs, ".json"))
      saveRDS(tools::md5sum(outputs), receipt)
      cat(pid, arm, "complete in", as.numeric(difftime(Sys.time(), t0, units = "secs")), "seconds\n")
      rm(result); gc()
    }
  }
}

audit_main <- function() {
  args <- strsplit(commandArgs(TRUE), "=", fixed = TRUE)
  if (any(lengths(args) != 2L)) stop("Use KEY=VALUE arguments")
  args <- setNames(lapply(args, `[`, 2L), vapply(args, `[`, character(1), 1L))
  get <- function(k, default) if (is.null(args[[k]])) default else args[[k]]
  root <- normalizePath(get("ROOT", file.path(.job_dir(), "external/fgiemit")), mustWork = TRUE)
  plots <- strsplit(get("PLOTS", "1001,1019"), ",", fixed = TRUE)[[1]]
  if (!length(plots) || anyDuplicated(plots) || !all(plots %in% c("1001", "1019")))
    stop("Audit is restricted to predeclared training plots 1001 and 1019")
  python <- get("EVAL_PYTHON", "python3")
  status <- system2(python, shQuote(c(file.path(.ROOT, "gpu/declare_transfer_audit.py"),
                                     "--root", root, "--verify")))
  if (status != 0L) stop("Audit declaration/integrity check failed")
  mode <- get("MODE", "infer")
  if (mode == "infer") audit_infer(root, plots, python) else if (mode == "analyze") {
    source(.find("transfer_audit_lib.R"))
    audit_analyze(root, plots, python)
  } else stop("MODE must be infer or analyze")
}

if (sys.nframe() == 0L) audit_main()
