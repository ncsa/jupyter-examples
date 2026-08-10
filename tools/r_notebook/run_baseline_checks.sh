#!/usr/bin/env bash
#
# Baseline check process for the r_notebook image. Run this against a
# freshly built image (or any environment with python3, jupyter, conda, and
# Rscript on PATH) whenever a new version of the image is created.
#
# Usage:
#   docker run --rm r_notebook:<tag> \
#     bash tools/r_notebook/run_baseline_checks.sh
#
# The GPU check is informational: it is expected to fail on hosts/images
# without a GPU attached and does not affect this script's overall exit code.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERALL_FAIL=0

NB_OUT_DIR="$(mktemp -d)"
trap 'rm -rf "$NB_OUT_DIR"' EXIT

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

run_check "Python script check" \
  python3 "$SCRIPT_DIR/baseline_check.py"

echo
echo "########################################"
echo "# Notebook: convert to script"
echo "########################################"
jupyter nbconvert --to script \
  --output "baseline_check" \
  --output-dir "$NB_OUT_DIR" \
  "$SCRIPT_DIR/baseline_check.ipynb"

# Run the converted script directly (rather than executing the notebook via
# a kernel) so its print() output streams straight to the console instead of
# being captured into the output .ipynb's cell metadata.
run_check "Notebook check" \
  python3 "$NB_OUT_DIR/baseline_check.py"

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
