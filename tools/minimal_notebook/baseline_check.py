#!/usr/bin/env python3
"""Baseline check: pip install, import, run a simple script, clean up, validate cleanup.

Simulates a normal user session on the minimal_notebook image, outside of a
notebook. Usage:

    python3 tools/minimal_notebook/baseline_check.py
"""

import subprocess
import sys

PACKAGES_TO_INSTALL = ["pandas", "tabulate"]


def run(*args, **kwargs):
    return subprocess.run(list(args), capture_output=True, text=True, **kwargs)


def installed_packages():
    result = run(sys.executable, "-m", "pip", "freeze", check=True)
    return set(result.stdout.splitlines())


def pip_install(packages):
    run(sys.executable, "-m", "pip", "install", "--quiet", *packages, check=True)


def pip_uninstall(packages):
    if packages:
        run(sys.executable, "-m", "pip", "uninstall", "--quiet", "-y", *packages, check=True)


def fresh_process_can_import(module_name):
    result = run(sys.executable, "-c", f"import {module_name}")
    return result.returncode == 0


def main():
    failures = []

    baseline = installed_packages()
    print(f"Baseline package count: {len(baseline)}")

    # Perform pip install
    pip_install(PACKAGES_TO_INSTALL)
    after_install = installed_packages()
    newly_installed = sorted(after_install - baseline)
    print("Newly installed packages:", newly_installed)
    if not newly_installed:
        failures.append("pip install did not add any new packages")

    # Import packages and run a simple script
    import pandas as pd
    from tabulate import tabulate

    milestones = [
        ("2024-01-15", "start"),
        ("2024-06-01", "midpoint"),
        ("2024-12-31", "end"),
    ]
    table_rows = [
        (pd.to_datetime(raw).strftime("%A, %B %d %Y"), label)
        for raw, label in milestones
    ]
    print(tabulate(table_rows, headers=["Date", "Milestone"]))

    expected_weekday = "Monday"
    actual_weekday = table_rows[0][0].split(",")[0]
    if actual_weekday != expected_weekday:
        failures.append(f"Expected {milestones[0][0]} to be a {expected_weekday}, got {actual_weekday}")
    else:
        print(f"PASS: date parsing + formatting produced expected weekday ({expected_weekday})")

    # Clean up the pip installs from earlier
    package_names = [pkg.split("==")[0] for pkg in newly_installed]
    pip_uninstall(package_names)
    print("Uninstalled:", package_names)

    # Validate cleanup was successful (fresh subprocess -- this process still
    # has pandas/tabulate cached in sys.modules from the import above)
    after_cleanup = installed_packages()
    leftover = after_cleanup - baseline
    missing = baseline - after_cleanup
    pandas_still_importable = fresh_process_can_import("pandas")
    tabulate_still_importable = fresh_process_can_import("tabulate")

    print("Leftover packages after cleanup:", sorted(leftover))
    print("Packages missing that were present at baseline:", sorted(missing))
    print("pandas importable in a fresh process after cleanup:", pandas_still_importable)
    print("tabulate importable in a fresh process after cleanup:", tabulate_still_importable)

    if leftover:
        failures.append(f"Leftover packages after cleanup: {sorted(leftover)}")
    if missing:
        failures.append(f"Packages missing after cleanup that were present at baseline: {sorted(missing)}")
    if pandas_still_importable:
        failures.append("pandas still importable in a fresh process after uninstall")
    if tabulate_still_importable:
        failures.append("tabulate still importable in a fresh process after uninstall")

    print()
    if failures:
        print("FAIL:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("PASS: environment restored to baseline after cleanup")
    return 0


if __name__ == "__main__":
    sys.exit(main())
