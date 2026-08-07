#!/usr/bin/env bash
#
# Baseline check: simulates a user creating an isolated conda environment,
# installing packages into it, running a script against them, uninstalling
# the packages, validating the uninstall, tearing the environment down, and
# validating the teardown.
#
# In production, JupyterHub's spawner redirects new environments and package
# downloads away from conda's default location (under /opt/conda, shared and
# ephemeral) to per-user directories under the user's home (persistent),
# already set in the environment this script runs in:
#
#   nb_user = user["eppn"].split('@')[0]
#   spawner.environment["CONDA_ENVS_PATH"] = f"/home/{nb_user}/.conda/envs"
#   spawner.environment["CONDA_PKGS_DIRS"] = f"/home/{nb_user}/.conda/pkgs"
#
# This check does not set those variables itself -- it verifies the ambient
# $CONDA_ENVS_PATH/$CONDA_PKGS_DIRS (however they got set) match those
# expected per-user paths. If they don't, the environment created for this
# check is torn down and the check fails immediately, since nothing that
# follows would be exercising the real, expected configuration.
#
# Usage:
#   bash tests/r_notebook/conda_env_check.sh
#
set -uo pipefail

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo "== $1 =="; }

summarize_and_exit() {
  echo
  echo "================================"
  echo " $PASS passed, $FAIL failed"
  echo "================================"
  [ "$FAIL" -eq 0 ] && exit 0 || exit 1
}

CONDA_BASE="$(conda info --base 2>/dev/null)"
if [ -z "$CONDA_BASE" ]; then
  echo "conda not found on PATH -- cannot run this check."
  exit 1
fi
# shellcheck disable=SC1091
source "$CONDA_BASE/etc/profile.d/conda.sh"

NB_USER="${NB_USER:-$(whoami)}"
EXPECTED_ENVS_PATH="/home/$NB_USER/.conda/envs"
EXPECTED_PKGS_DIRS="/home/$NB_USER/.conda/pkgs"

ENV_NAME="baseline_check_env_$$"

cleanup_env() {
  conda env remove -y -n "$ENV_NAME" >/dev/null 2>&1 || true
}
trap cleanup_env EXIT

section "Create environment"
if conda create -y -q -n "$ENV_NAME" python=3.11 numpy pyyaml >/dev/null 2>&1; then
  pass "conda create succeeded for env '$ENV_NAME'"
else
  fail "conda create failed for env '$ENV_NAME'"
  summarize_and_exit
fi

section "CONDA_ENVS_PATH / CONDA_PKGS_DIRS match the expected per-user paths"
PATHS_OK=true

if [ "${CONDA_ENVS_PATH:-}" = "$EXPECTED_ENVS_PATH" ]; then
  pass "\$CONDA_ENVS_PATH is $EXPECTED_ENVS_PATH"
else
  fail "\$CONDA_ENVS_PATH is '${CONDA_ENVS_PATH:-<unset>}', expected $EXPECTED_ENVS_PATH"
  PATHS_OK=false
fi

if [ "${CONDA_PKGS_DIRS:-}" = "$EXPECTED_PKGS_DIRS" ]; then
  pass "\$CONDA_PKGS_DIRS is $EXPECTED_PKGS_DIRS"
else
  fail "\$CONDA_PKGS_DIRS is '${CONDA_PKGS_DIRS:-<unset>}', expected $EXPECTED_PKGS_DIRS"
  PATHS_OK=false
fi

if [ "$PATHS_OK" = false ]; then
  cleanup_env
  trap - EXIT
  summarize_and_exit
fi

ENV_DIR="$CONDA_ENVS_PATH/$ENV_NAME"

section "Install packages"
NUMPY_PATH=$(conda run -n "$ENV_NAME" python -c "import numpy; print(numpy.__file__)" 2>/dev/null)
case "$NUMPY_PATH" in
  "$ENV_DIR"/*) pass "numpy installed inside env at $NUMPY_PATH" ;;
  *) fail "numpy path '$NUMPY_PATH' is not inside $ENV_DIR" ;;
esac

YAML_PATH=$(conda run -n "$ENV_NAME" python -c "import yaml; print(yaml.__file__)" 2>/dev/null)
case "$YAML_PATH" in
  "$ENV_DIR"/*) pass "pyyaml installed inside env at $YAML_PATH" ;;
  *) fail "pyyaml path '$YAML_PATH' is not inside $ENV_DIR" ;;
esac

section "Run a script utilizing the installed packages"
SCRIPT_OUTPUT=$(conda run -n "$ENV_NAME" python -c '
import numpy as np
import yaml

data = {"values": np.arange(1, 6).tolist()}
total = int(np.sum(data["values"]))
print(yaml.safe_dump({"total": total}).strip())
' 2>/dev/null)

if [ "$SCRIPT_OUTPUT" = "total: 15" ]; then
  pass "script using numpy + pyyaml produced expected output ($SCRIPT_OUTPUT)"
else
  fail "script produced unexpected output: '$SCRIPT_OUTPUT'"
fi

section "Uninstall packages"
if conda remove -y -n "$ENV_NAME" numpy pyyaml >/dev/null 2>&1; then
  pass "conda remove succeeded for numpy and pyyaml in '$ENV_NAME'"
else
  fail "conda remove failed for numpy/pyyaml in '$ENV_NAME'"
fi

section "Validate the uninstall"
if conda run -n "$ENV_NAME" python -c "import numpy" >/dev/null 2>&1; then
  fail "numpy is still importable in '$ENV_NAME' after uninstall"
else
  pass "numpy is no longer importable in '$ENV_NAME'"
fi

if conda run -n "$ENV_NAME" python -c "import yaml" >/dev/null 2>&1; then
  fail "pyyaml is still importable in '$ENV_NAME' after uninstall"
else
  pass "pyyaml is no longer importable in '$ENV_NAME'"
fi

section "Tear down the test environment"
if conda env remove -y -n "$ENV_NAME" >/dev/null 2>&1; then
  pass "conda env remove succeeded for '$ENV_NAME'"
else
  fail "conda env remove failed for '$ENV_NAME'"
fi

section "Validate the test environment was torn down"
if conda env list | grep -qw "$ENV_NAME"; then
  fail "'$ENV_NAME' still listed in 'conda env list' after removal"
else
  pass "'$ENV_NAME' no longer listed in 'conda env list'"
fi

if [ -d "$ENV_DIR" ]; then
  fail "environment directory $ENV_DIR still exists after removal"
else
  pass "environment directory $ENV_DIR no longer exists"
fi

trap - EXIT
summarize_and_exit
