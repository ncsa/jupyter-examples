# vscode baseline checks

Baseline checks to run against a newly built `vscode` image, simulating
normal user activity to catch regressions before the image ships.

Run everything with:

```bash
bash tests/vscode/run_baseline_checks.sh
```

## Checks

- **`baseline_check.py`** — pip installs a package, imports it and runs a small
  script, then uninstalls it and verifies the environment is back to its
  pre-check state.
- **`baseline_check.ipynb`** — the same install / use / clean up / validate
  pattern as `baseline_check.py`, but as a notebook, using `pandas` for a
  computational step.
- **`dockerfile_config_check.sh`** — validates the custom configuration
  layered on top of the base image by the Dockerfile: code-server itself
  (installed, and reporting a version), the custom `vscode_proxy` package
  (`docker/vscode/vscode_proxy/`) that serves it through Jupyter — importable,
  registered with jupyter-server-proxy under the `vscode` entry-point name,
  and returning a valid launch config — the apt packages installed alongside
  them, the `$NB_USER` home cache directory ownership (explicitly `chown`'d
  in the Dockerfile), the conda `profile.d` init script, and the final
  non-root user.
- **`conda_env_check.sh`** — simulates a user creating an isolated conda
  environment: create it, install packages, run a script using them,
  uninstall the packages and validate the uninstall, then tear the
  environment down and validate the teardown.
- **`gpu_check.sh`** — reports whether an NVIDIA GPU is visible via
  `nvidia-smi`. This is informational only: it's expected to fail on
  images/hosts without a GPU attached, and does not affect the overall
  result of `run_baseline_checks.sh`.

`run_baseline_checks.sh` runs all of the above and prints a pass/fail summary.
