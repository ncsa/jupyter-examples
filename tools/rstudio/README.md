# rstudio baseline checks

Baseline checks to run against a newly built `rstudio` image, catching
regressions before the image ships.

Unlike the other image test suites in this repo, this one is geared towards
the RStudio application itself -- R, RStudio Server, the packages it ships,
and its Jupyter integration -- rather than the Jupyter notebook it runs on
top of. There is no Python/pip/notebook check here.

Run everything with:

```bash
bash tests/rstudio/run_baseline_checks.sh
```

## Checks

- **`dockerfile_config_check.sh`** — validates the custom configuration
  layered on top of the base image by the Dockerfile: R identity (RStudio
  Server is pinned via `rserver.conf` at the conda R shipped by the
  r-notebook base image, not a separate apt-installed R), the
  `rserver.conf`/`rsession.conf` settings themselves, test libcurl/internet
  connectivity, RStudio Server itself (installed,
  version reported, and passing `rstudio-server verify-installation`),
  `tidyverse`/`data.table` being loadable, the apt packages installed
  alongside them, that the rsession `LD_LIBRARY_PATH` override doesn't break
  other tools (git/curl/ssh), the conda `profile.d` init script, the
  `jupyter-rsession-proxy` integration that serves RStudio Server through
  Jupyter, conda environment write permissions, and the final non-root user.
- **`baseline_check.R`** — simulates a normal R user session:
  `install.packages()` a CRAN package, use it for a calculation,
  `remove.packages()` it, then validate the removal actually took effect.
  Runs via `Rscript` against the same conda R installation and package
  library that RStudio Server sessions use.
- **`conda_env_check.sh`** — simulates a user creating an isolated conda
  environment: create it, install packages, run a script using them,
  uninstall the packages and validate the uninstall, then tear the
  environment down and validate the teardown.
- **`gpu_check.sh`** — reports whether an NVIDIA GPU is visible via
  `nvidia-smi`. This is informational only: it's expected to fail on
  images/hosts without a GPU attached, and does not affect the overall
  result of `run_baseline_checks.sh`.

`run_baseline_checks.sh` runs all of the above and prints a pass/fail summary.
