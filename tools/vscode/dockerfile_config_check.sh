#!/usr/bin/env bash
#
# Baseline check: validates the custom configuration layered on top of the
# base image by docker/vscode/Dockerfile -- code-server itself, the custom
# vscode_proxy package that serves it through Jupyter, the apt packages
# installed alongside them, the conda profile.d init script, and the final
# non-root user.
#
# Usage:
#   bash tests/vscode/dockerfile_config_check.sh
#
set -uo pipefail

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo "== $1 =="; }

# 1. code-server itself -- the actual application this image exists to
#    serve, installed via the official install.sh script.
section "code-server installation"
command -v code-server >/dev/null 2>&1 \
  && pass "code-server is present on PATH" \
  || fail "code-server is missing from PATH"

CODE_SERVER_VERSION_OUT=$(code-server --version 2>&1 | head -1)
if [ -n "$CODE_SERVER_VERSION_OUT" ]; then
  pass "code-server --version reports: $CODE_SERVER_VERSION_OUT"
else
  fail "code-server --version produced no output"
fi

# 2. The custom vscode_proxy package (docker/vscode/vscode_proxy/) -- the
#    mechanism that actually serves code-server through Jupyter, rather
#    than requiring a separate port/URL. It plugs into jupyter-server-proxy
#    as a backend registered under the entry-point name "vscode".
section "vscode_proxy integration"
python3 -c "import vscode" 2>/dev/null \
  && pass "vscode module importable" \
  || fail "vscode module not importable"

python3 -c "
from importlib.metadata import entry_points
import sys
names = [ep.name for ep in entry_points(group='jupyter_serverproxy_servers')]
sys.exit(0 if 'vscode' in names else 1)
" 2>/dev/null \
  && pass "vscode proxy backend registered with jupyter-server-proxy" \
  || fail "vscode proxy backend not found in jupyter_serverproxy_servers entry points"

VSCODE_SETUP_OUT=$(python3 -c "
import vscode
config = vscode.setup_vscode()
assert len(config['command']) == 3
assert config['port'] == 8080
assert 'PASSWORD' in config['environment']
print('ok')
" 2>&1)
if [ "$VSCODE_SETUP_OUT" = "ok" ]; then
  pass "vscode.setup_vscode() returns a valid code-server launch config"
else
  fail "vscode.setup_vscode() did not return the expected config: $VSCODE_SETUP_OUT"
fi

# 3. The apt packages the Dockerfile installs alongside code-server.
section "apt packages installed by the Dockerfile"
for bin in gcc g++ make cmake curl jq; do
  command -v "$bin" >/dev/null 2>&1 \
    && pass "$bin is present on PATH" \
    || fail "$bin is missing from PATH"
done

# 4. The Dockerfile explicitly chowns $NB_USER's .cache dir after installing
#    vscode_proxy (pip as root leaves it root-owned otherwise), since
#    code-server itself writes there at runtime.
section "Home cache directory ownership"
CACHE_DIR="$HOME/.cache"
if [ -d "$CACHE_DIR" ]; then
  CACHE_OWNER=$(stat -c "%U" "$CACHE_DIR" 2>/dev/null || stat -f "%Su" "$CACHE_DIR" 2>/dev/null)
  if [ "$CACHE_OWNER" = "$(whoami)" ]; then
    pass "$CACHE_DIR is owned by $(whoami)"
  else
    fail "$CACHE_DIR is owned by '$CACHE_OWNER', expected $(whoami)"
  fi
else
  fail "$CACHE_DIR does not exist"
fi

# 5. The profile.d script the Dockerfile writes to enable conda
#    activate/deactivate in login shells.
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

# 6. The Dockerfile ends by dropping back from root to $NB_USER.
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
