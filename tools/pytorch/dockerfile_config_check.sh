#!/usr/bin/env bash
#
# Baseline check: validates the custom configuration layered on top of the
# base image by docker/pytorch/Dockerfile -- the CUDA toolchain environment,
# the conda profile.d init script, the apt packages installed alongside it,
# the pip packages baked into the image (torch/torchvision/torchaudio/
# ISLP/nvitop), and the final non-root user.
#
# Usage:
#   bash tools/pytorch/dockerfile_config_check.sh
#
set -uo pipefail

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo "== $1 =="; }

# 1. The CUDA toolchain environment the Dockerfile sets up.
section "CUDA environment"
case ":$PATH:" in
  *:/usr/local/cuda/bin:*) pass "\$PATH includes /usr/local/cuda/bin" ;;
  *) fail "\$PATH does not include /usr/local/cuda/bin (PATH=$PATH)" ;;
esac

case ":${LD_LIBRARY_PATH:-}:" in
  *:/usr/local/cuda/lib64:*) pass "\$LD_LIBRARY_PATH includes /usr/local/cuda/lib64" ;;
  *) fail "\$LD_LIBRARY_PATH does not include /usr/local/cuda/lib64 (LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-<unset>})" ;;
esac

command -v nvcc >/dev/null 2>&1 \
  && pass "nvcc is present on PATH" \
  || fail "nvcc is missing from PATH"

NVCC_VERSION_OUT=$(nvcc --version 2>&1)
if echo "$NVCC_VERSION_OUT" | grep -qi "release 12.8"; then
  pass "nvcc reports release 12.8 (matches cuda-compiler-12-8)"
else
  fail "nvcc --version did not report release 12.8: $NVCC_VERSION_OUT"
fi

# 2. The profile.d script the Dockerfile writes to enable conda
#    activate/deactivate in login shells, without a full `conda init`.
section "Conda profile.d initialization script"
PROFILE_SCRIPT="/etc/profile.d/init_conda.sh"
if [ -f "$PROFILE_SCRIPT" ]; then
  pass "$PROFILE_SCRIPT exists"
else
  fail "$PROFILE_SCRIPT is missing"
fi

grep -q '_CONDA_ROOT=/opt/conda' "$PROFILE_SCRIPT" 2>/dev/null \
  && pass "$PROFILE_SCRIPT sets _CONDA_ROOT=/opt/conda" \
  || fail "$PROFILE_SCRIPT does not set _CONDA_ROOT=/opt/conda"

grep -q 'etc/profile.d/conda.sh' "$PROFILE_SCRIPT" 2>/dev/null \
  && pass "$PROFILE_SCRIPT sources conda.sh" \
  || fail "$PROFILE_SCRIPT does not source conda.sh"

CONDA_TYPE=$(bash -lc 'type conda' 2>&1)
if echo "$CONDA_TYPE" | grep -qi 'function'; then
  pass "'conda' is a shell function in a login shell (conda.sh was sourced via profile.d)"
else
  fail "'conda' is not a shell function in a login shell: $CONDA_TYPE"
fi

CONDA_ACTIVATE_OUT=$(bash -lc 'conda activate base && python -c "import sys; print(sys.prefix)"' 2>&1)
if [ "$CONDA_ACTIVATE_OUT" = "/opt/conda" ]; then
  pass "'conda activate base' works in a login shell (sys.prefix=/opt/conda)"
else
  fail "'conda activate base' did not resolve to /opt/conda: $CONDA_ACTIVATE_OUT"
fi

# 3. The apt packages the Dockerfile installs on top of the base image
#    (nvcc itself is checked above, alongside its version).
section "apt packages installed by the Dockerfile"
for bin in gcc g++ make cmake jq; do
  command -v "$bin" >/dev/null 2>&1 \
    && pass "$bin is present on PATH" \
    || fail "$bin is missing from PATH"
done

# 4. The pip packages the Dockerfile bakes into the image.
section "pip packages installed by the Dockerfile"
for module_import in "ISLP:ISLP" "torch:torch" "torchvision:torchvision" "torchaudio:torchaudio" "nvitop:nvitop"; do
  label="${module_import%%:*}"
  module="${module_import##*:}"
  python3 -c "import $module" >/dev/null 2>&1 \
    && pass "$label is importable" \
    || fail "$label is not importable"
done

TORCH_CUDA_VERSION=$(python3 -c "import torch; print(torch.version.cuda)" 2>/dev/null)
if [ -n "$TORCH_CUDA_VERSION" ] && [ "$TORCH_CUDA_VERSION" != "None" ]; then
  pass "torch was built with CUDA support (torch.version.cuda=$TORCH_CUDA_VERSION)"
else
  fail "torch does not report CUDA support (torch.version.cuda=${TORCH_CUDA_VERSION:-<unavailable>}) -- a CPU-only wheel may have been installed"
fi

# 5. The Dockerfile ends by dropping back from root to $NB_USER.
section "Final image user"
CURRENT_USER=$(whoami)
if [ "$CURRENT_USER" != "root" ]; then
  pass "running as non-root user ($CURRENT_USER)"
else
  fail "running as root -- Dockerfile's final USER \$NB_USER did not take effect"
fi

if [ -n "${NB_USER:-}" ]; then
  if [ "$CURRENT_USER" = "$NB_USER" ]; then
    pass "current user matches \$NB_USER ($NB_USER)"
  else
    fail "current user '$CURRENT_USER' does not match \$NB_USER ('$NB_USER')"
  fi
fi

echo
echo "================================"
echo " $PASS passed, $FAIL failed"
echo "================================"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
