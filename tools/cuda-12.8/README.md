# CUDA 12.8 compatibility check

Checks that a CUDA 12.8 image (`pytorch`: `nvcc` 12.8 plus a CUDA 12.x build of
`torch`) works on the GPU node it lands on. It's meant to be run unchanged on
an r570 node (`nvidia-smi` reports `CUDA Version: 12.8`) and again on an r580+
node (`CUDA Version: 13.x`), to confirm the driver upgrade doesn't break
existing CUDA 12 workloads.

Run it from JupyterLab on a GPU server with **Kernel > Restart Kernel and Run
All Cells**, or headless with:

```bash
jupyter nbconvert --to notebook --execute tools/cuda-12.8/cuda_compat_check.ipynb
```

## Checks

- **Driver and GPU**: `nvidia-smi` sees the GPU; records the driver version,
  compute capability, MIG mode and the driver's maximum CUDA version (from
  `cuDriverGetVersion()`).
- **CUDA toolkit in the image**: `nvcc` and `libcudart` both report 12.8, and
  `torch` was built with CUDA 12.x.
- **Compatibility mode**: names the rule that lets the image's CUDA run on this
  driver (native, backward compatibility, minor version compatibility, or
  incompatible) and fails only if incompatible.
- **nvcc compile and run**: builds a vector-add kernel two ways, as native
  SASS for the GPU's architecture and as PTX only (JIT-compiled by the driver),
  and checks both produce correct results. The PTX build is expected to fail
  only under minor version compatibility, and the check accounts for that.
  **Currently disabled** (`RUN_NVCC_CHECKS = False`, reported as SKIP):
  CUDA 12.8's `nvcc` supports gcc 14 and older, and the image's default `gcc`
  is newer, so every build fails. Set it to `True` once the image's `nvcc`
  version is changed.
- **PyTorch on the GPU**: cuBLAS matmul, cuDNN conv2d, cuFFT and cuRAND results
  are compared against the CPU, plus a short training loop.

Allocations stay well under 1 GB, so it's safe on time-sliced and MIG GPUs.

## Expected results

| Node driver | `nvidia-smi` CUDA Version | Mode for a 12.8 image | Expected |
|---|---|---|---|
| r570 | 12.8 | native | all PASS |
| r580 and newer | 13.x | backward compatibility | all PASS |

A check that passes on r570 and fails on r580+ is a regression from the driver
upgrade.

## Comparing runs

The last cell writes
`cuda-check-results/<hostname>_driver-<version>_<timestamp>.json` (relative to
the notebook's working directory), with the driver, toolkit and `torch` CUDA
versions and every check result. Diff the files from the two nodes to compare.
