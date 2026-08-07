#!/usr/bin/env Rscript
#
# Baseline check: installs an R package, uses it for a calculation, uninstalls
# it, then validates the uninstall actually removed it.
#
# Simulates a normal R user session on the rstudio image -- run via Rscript
# rather than through the RStudio Server web UI, but against the exact same R
# installation and package library that RStudio Server sessions use: this
# Dockerfile points RStudio Server at the conda R shipped by the r-notebook
# base image (via rserver.conf) rather than installing a separate R, and
# that conda env is owned by $NB_USER, so its library is directly writable.
# moments/fortunes are unrelated to the tidyverse/data.table this Dockerfile
# preinstalls, so this exercises a genuine install-from-CRAN-source path
# (build-essential/cmake toolchain) rather than one already satisfied.
#
#   Rscript tests/rstudio/baseline_check.R
#
PACKAGES_TO_INSTALL <- c("moments", "fortunes")

failures <- character(0)

# Defensive fallback only: if the default library somehow isn't writable
# (e.g. this script is adapted for a setup where R isn't the conda R owned
# by $NB_USER), fall back to a personal library the way an interactive R
# session (RStudio's IDE) would after its one-time "create a personal
# library?" prompt -- a plain, non-interactive `Rscript` run like this one
# needs it created explicitly. Left untouched when the default library (the
# conda env) is already writable, which is the expected case here.
if (file.access(.libPaths()[1], 2) != 0) {
  user_lib <- Sys.getenv("R_LIBS_USER")
  if (nzchar(user_lib)) {
    if (!dir.exists(user_lib)) {
      dir.create(user_lib, recursive = TRUE, showWarnings = FALSE)
    }
    if (!(user_lib %in% .libPaths())) {
      .libPaths(c(user_lib, .libPaths()))
    }
  }
}

installed_packages <- function() {
  sort(rownames(installed.packages()))
}

# Re-checks importability in a fresh Rscript subprocess -- this session may
# still have a package's namespace cached even after remove.packages().
fresh_process_can_load <- function(package_name) {
  status <- system2(
    "Rscript",
    args = c("-e", shQuote(sprintf(
      "quit(status = if (requireNamespace('%s', quietly = TRUE)) 0 else 1)",
      package_name
    ))),
    stdout = FALSE, stderr = FALSE
  )
  status == 0
}

baseline <- installed_packages()
cat(sprintf("Baseline package count: %d\n", length(baseline)))

# Install a package
install.packages(PACKAGES_TO_INSTALL, repos = "https://cloud.r-project.org", quiet = TRUE)

after_install <- installed_packages()
newly_installed <- setdiff(after_install, baseline)
cat("Newly installed packages:", paste(newly_installed, collapse = ", "), "\n")
if (length(newly_installed) == 0) {
  failures <- c(failures, "install.packages() did not add any new packages")
}

# Perform a calculation using the package
library(moments)
values <- c(1, 2, 3, 4, 5, 6, 7, 8, 9)
result_skewness <- skewness(values)
result_kurtosis <- kurtosis(values)

cat(sprintf("skewness(values) = %f\n", result_skewness))
cat(sprintf("kurtosis(values) = %f\n", result_kurtosis))

if (abs(result_skewness) > 1e-9 || abs(result_kurtosis - 1.77) > 1e-6) {
  failures <- c(failures, sprintf(
    "Expected skewness=0, kurtosis=1.77 for this symmetric sample, got skewness=%f, kurtosis=%f",
    result_skewness, result_kurtosis
  ))
} else {
  cat("PASS: moments::skewness/kurtosis computation produced expected results\n")
}

# Clean up the packages installed earlier
if (length(newly_installed) > 0) {
  remove.packages(newly_installed)
}
cat("Uninstalled:", paste(newly_installed, collapse = ", "), "\n")

# Validate the uninstall was successful. Checks re-importability of whatever
# was actually newly installed (newly_installed), not a fixed package name --
# if a base image already ships one of PACKAGES_TO_INSTALL, that package is
# correctly never removed, so it should stay loadable rather than being
# flagged as a cleanup failure.
after_cleanup <- installed_packages()
leftover <- setdiff(after_cleanup, baseline)
missing <- setdiff(baseline, after_cleanup)
still_loadable <- stats::setNames(
  vapply(newly_installed, fresh_process_can_load, logical(1)),
  newly_installed
)

cat("Leftover packages after cleanup:", paste(leftover, collapse = ", "), "\n")
cat("Packages missing that were present at baseline:", paste(missing, collapse = ", "), "\n")
for (name in names(still_loadable)) {
  cat(sprintf("%s loadable in a fresh process after cleanup: %s\n", name, still_loadable[[name]]))
}

if (length(leftover) > 0) {
  failures <- c(failures, sprintf("Leftover packages after cleanup: %s", paste(leftover, collapse = ", ")))
}
if (length(missing) > 0) {
  failures <- c(failures, sprintf(
    "Packages missing after cleanup that were present at baseline: %s",
    paste(missing, collapse = ", ")
  ))
}
for (name in names(still_loadable)) {
  if (still_loadable[[name]]) {
    failures <- c(failures, sprintf("%s still loadable in a fresh process after uninstall", name))
  }
}

cat("\n")
if (length(failures) > 0) {
  cat("FAIL:\n")
  for (f in failures) cat(sprintf("  - %s\n", f))
  quit(status = 1)
}

cat("PASS: environment restored to baseline after cleanup\n")
quit(status = 0)
