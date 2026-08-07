#!/usr/bin/env Rscript
#
# Baseline check: installs an R package, uses it for a calculation, uninstalls
# it, then validates the uninstall actually removed it.
#
# Simulates a normal R user session on the r_notebook image. Usage:
#
#   Rscript tests/r_notebook/baseline_check.R
#
PACKAGES_TO_INSTALL <- c("moments", "fortunes")

failures <- character(0)

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
