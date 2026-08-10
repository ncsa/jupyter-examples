#!/usr/bin/env bash
#
# Baseline check process for the rstudio image. Run this against a freshly
# built image (or any environment with R and conda on PATH) whenever a new
# version of the image is created.
#
# Unlike the other image test suites in this repo, this one is geared
# towards the RStudio application itself (R, RStudio Server, the packages
# it ships, its Jupyter integration) rather than the Jupyter notebook it
# runs on top of -- there is no Python/pip/notebook check here.
#
# Usage:
#   docker run --rm rstudio:<tag> \
#     bash tools/rstudio/run_baseline_checks.sh
#
# The GPU check is informational: it is expected to fail on hosts/images
# without a GPU attached and does not affect this script's overall exit code.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERALL_FAIL=0

run_check() {
  local name="$1"; shift
  echo
  echo "########################################"
  echo "# $name"
  echo "########################################"
  if "$@"; then
    echo "--> $name: PASS"
  else
    echo "--> $name: FAIL"
    OVERALL_FAIL=1
  fi
}

run_check "Dockerfile custom configuration check" \
  bash "$SCRIPT_DIR/dockerfile_config_check.sh"

run_check "R script check" \
  Rscript "$SCRIPT_DIR/baseline_check.R"

run_check "Conda environment check" \
  bash "$SCRIPT_DIR/conda_env_check.sh"

echo
echo "########################################"
echo "# GPU check (informational -- expected to fail without a GPU)"
echo "########################################"
if bash "$SCRIPT_DIR/gpu_check.sh"; then
  echo "--> GPU check: PASS (GPU detected)"
else
  echo "--> GPU check: FAIL (no GPU detected -- expected on non-GPU hosts, not counted against overall result)"
fi

echo
if [ "$OVERALL_FAIL" -eq 0 ]; then
  echo "================================"
  echo " Baseline checks: ALL PASS"
  echo "================================"
  exit 0
else
  echo "================================"
  echo " Baseline checks: FAILURES DETECTED"
  echo "================================"
  exit 1
fi
