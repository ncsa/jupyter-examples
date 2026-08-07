#!/usr/bin/env bash
#
# Baseline check: validates the custom configuration layered on top of the
# base image by docker/rstudio/Dockerfile -- RStudio Server pinned at the
# conda R shipped by the r-notebook base image (via rserver.conf, rather
# than installing a second apt-based R), R's internet/libcurl connectivity,
# the RStudio Server installation itself, data.table (added via mamba on
# top of the base image's tidyverse), the apt packages installed alongside
# them, the conda profile.d init script, and the jupyter-rsession-proxy
# integration that serves RStudio Server through Jupyter.
#
# Usage:
#   bash tests/rstudio/dockerfile_config_check.sh
#
set -uo pipefail

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo "== $1 =="; }

# 1. R identity -- the Dockerfile deliberately points RStudio Server at the
#    conda R shipped by the r-notebook base image, rather than installing a
#    second, separately-linked R.
section "R identity"
R_PATH=$(command -v R || true)
if [ "$R_PATH" = "/opt/conda/bin/R" ]; then
  pass "which R resolves to /opt/conda/bin/R"
else
  fail "which R resolved to '$R_PATH', expected /opt/conda/bin/R"
fi

R_HOME=$(Rscript -e 'cat(R.home())' 2>/dev/null)
if [ "$R_HOME" = "/opt/conda/lib/R" ]; then
  pass "R.home() is /opt/conda/lib/R"
else
  fail "R.home() is '$R_HOME', expected /opt/conda/lib/R"
fi

# 2. rserver.conf/rsession.conf pins from the Dockerfile.
section "rserver.conf / rsession.conf configuration"
grep -q "^rsession-which-r=/opt/conda/bin/R$" /etc/rstudio/rserver.conf 2>/dev/null \
  && pass "rsession-which-r set correctly" \
  || fail "rsession-which-r missing/incorrect in /etc/rstudio/rserver.conf"

grep -q "^rsession-ld-library-path=/opt/conda/lib$" /etc/rstudio/rserver.conf 2>/dev/null \
  && pass "rsession-ld-library-path set correctly" \
  || fail "rsession-ld-library-path missing/incorrect in /etc/rstudio/rserver.conf"

grep -q "^posit-assistant-enabled=0$" /etc/rstudio/rsession.conf 2>/dev/null \
  && pass "posit-assistant-enabled=0 set correctly" \
  || fail "posit-assistant-enabled=0 missing/incorrect in /etc/rstudio/rsession.conf"

# 3. R's internet/libcurl connectivity.
section "Internet / libcurl"
LIBCURL_CAP=$(Rscript -e 'cat(capabilities("libcurl"))' 2>/dev/null)
[ "$LIBCURL_CAP" = "TRUE" ] && pass "capabilities(libcurl) is TRUE" || fail "capabilities(libcurl) is $LIBCURL_CAP"

Rscript -e '
con <- url("https://cloud.r-project.org/src/contrib/PACKAGES")
ok <- tryCatch({ readLines(con, n = 1); TRUE }, error = function(e) FALSE)
close(con)
quit(status = if (ok) 0 else 1)
' 2>/dev/null \
  && pass "can open a libcurl URL connection to CRAN" \
  || fail "opening a URL connection to CRAN failed (internet routines / proxy issue)"

# 4. RStudio Server itself -- the actual application this image exists to
#    serve.
section "RStudio Server installation"
if command -v rstudio-server >/dev/null 2>&1; then
  pass "rstudio-server binary is present on PATH"
  RSTUDIO_VERSION_OUT=$(rstudio-server version 2>&1)
  if [ -n "$RSTUDIO_VERSION_OUT" ]; then
    pass "rstudio-server version reports: $RSTUDIO_VERSION_OUT"
  else
    fail "rstudio-server version produced no output"
  fi
  # verify-installation launches a real rsession (via PAM) to test end to
  # end, which requires root -- it silently fails (no output, just a
  # nonzero exit) for the non-root $NB_USER this container normally runs
  # as, and that user has no passwordless sudo. Run this one check with
  # `docker exec -u root ...` to get a real answer; otherwise skip it
  # rather than reporting a false failure.
  if [ "$(whoami)" = "root" ]; then
    if rstudio-server verify-installation 2>&1; then
      pass "rstudio-server verify-installation succeeded"
    else
      fail "rstudio-server verify-installation failed"
    fi
  else
    echo "  SKIP: rstudio-server verify-installation requires root -- re-run this script via 'docker exec -u root ...' to check it"
  fi
else
  fail "rstudio-server binary not found on PATH"
fi

# 5. tidyverse (from the r-notebook base image's conda R) and data.table
#    (added on top via mamba, into the same conda env).
section "Pre-installed R packages"
for pkg in tidyverse data.table; do
  Rscript -e "quit(status = if (requireNamespace('$pkg', quietly = TRUE)) 0 else 1)" >/dev/null 2>&1 \
    && pass "$pkg is installed and loadable" \
    || fail "$pkg failed to load"
done

# 6. The apt packages the Dockerfile installs alongside RStudio Server.
section "apt packages installed by the Dockerfile"
for bin in gcc g++ make cmake jq; do
  command -v "$bin" >/dev/null 2>&1 \
    && pass "$bin is present on PATH" \
    || fail "$bin is missing from PATH"
done

# 7. Session-wide LD_LIBRARY_PATH didn't break other tools that inherit it
#    from rsession.
section "Non-R tooling under the rsession LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="/opt/conda/lib:${LD_LIBRARY_PATH:-}"
for cmd in "git --version" "curl --version" "ssh -V"; do
  bin=$(echo "$cmd" | cut -d' ' -f1)
  if command -v "$bin" >/dev/null 2>&1; then
    if out=$(eval "$cmd" 2>&1); then
      pass "'$cmd' runs cleanly with /opt/conda/lib on LD_LIBRARY_PATH"
    else
      fail "'$cmd' failed with /opt/conda/lib on LD_LIBRARY_PATH: $out"
    fi
  fi
done
unset LD_LIBRARY_PATH

# 8. The profile.d script the Dockerfile writes to enable conda
#    activate/deactivate in login shells -- per the Dockerfile's own comment,
#    this is meant to make conda envs available from within RStudio sessions.
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

# 9. jupyter-rsession-proxy -- the mechanism that actually serves RStudio
#    Server through Jupyter, rather than requiring a separate port/URL. It
#    plugs into jupyter-server-proxy as a backend registered under the
#    entry-point name "rstudio" (not "rsession", despite the package name --
#    confirmed via importlib.metadata.entry_points).
section "jupyter-rsession-proxy integration"
python3 -c "import jupyter_rsession_proxy" 2>/dev/null \
  && pass "jupyter_rsession_proxy python module importable" \
  || fail "jupyter_rsession_proxy not importable"

python3 -c "
from importlib.metadata import entry_points
import sys
names = [ep.name for ep in entry_points(group='jupyter_serverproxy_servers')]
sys.exit(0 if 'rstudio' in names else 1)
" 2>/dev/null \
  && pass "rstudio proxy backend registered with jupyter-server-proxy" \
  || fail "rstudio proxy backend not found in jupyter_serverproxy_servers entry points"

# 10. Conda environment write permission for the notebook user (validates
#     the USER $NB_UID wrapping around the mamba install of r-data.table,
#     and that RStudio sessions can install.packages() into the shared env).
section "Conda environment permissions"
touch /opt/conda/.write_test 2>/dev/null \
  && { rm -f /opt/conda/.write_test; pass "/opt/conda is writable by current user ($(whoami))"; } \
  || fail "/opt/conda is NOT writable by current user ($(whoami)) -- install.packages()/mamba installs as this user will fail"

# 11. The Dockerfile ends by dropping back from root to $NB_USER.
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
