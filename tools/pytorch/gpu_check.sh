#!/usr/bin/env bash
#
# Baseline check: reports whether an NVIDIA GPU is visible via nvidia-smi.
#
# This check is EXPECTED to fail (exit 1) on hosts/images that don't have a
# GPU attached -- even though the pytorch image is built with CUDA support,
# it's still commonly run on CPU-only hosts (e.g. CI runners). It is
# informational and should not be treated as a hard failure of the image;
# see run_baseline_checks.sh for how it's excluded from the overall result.
#
# Usage:
#   bash tests/pytorch/gpu_check.sh
#
# Exit codes:
#   0 - nvidia-smi is present and reported GPU status successfully
#   1 - nvidia-smi is missing, or present but reported an error (no devices,
#       driver mismatch, etc.) -- expected when no GPU is attached
#
set -uo pipefail

echo "== GPU check =="

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "nvidia-smi not found on PATH -- no NVIDIA GPU/driver present on this host."
  echo "This is EXPECTED for environments without a GPU attached."
  exit 1
fi

if nvidia-smi; then
  echo "PASS: nvidia-smi reported GPU status successfully."
  exit 0
else
  echo "nvidia-smi is present but returned an error (no devices visible, driver mismatch, etc.)."
  echo "This is EXPECTED on hosts without a GPU attached."
  exit 1
fi
