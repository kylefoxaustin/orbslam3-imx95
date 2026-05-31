# ORB-SLAM3 → NXP i.MX 95 (qemu-imx95)

An ORB-SLAM3 build characterized on an x86 baseline and then **cross-compiled and run end-to-end on an
emulated NXP i.MX 95 (Cortex-A55)** under [qemu-imx95](https://github.com/kylefoxaustin/qemu-imx95).

ORB-SLAM3 is the canonical classical (feature-based) visual-SLAM stack — a substantial real-world C++
application (OpenCV + Eigen + g2o + DBoW2 + Sophus). This repo records getting it built, measured, and
running on the i.MX 95 target class.

## Goals

1. **Reproducible build.** Get a clean ORB-SLAM3 build on a modern toolchain (Ubuntu 22.04 / GCC 13),
   documenting every fix so it's reproducible rather than a one-off.
2. **Workload characterization.** Measure ORB-SLAM3 as a workload on an x86 baseline — build cost,
   whether it converges on a standard dataset (EuRoC MH_01), and its runtime shape: CPU- vs
   memory-bound, cache behavior, thread/core usage, memory footprint, and per-frame latency.
3. **Cross-compile + run on i.MX 95.** Establish whether a real SLAM stack of this size is portable to,
   and runs correctly on, the NXP i.MX 95 (Cortex-A55) Linux userspace under qemu-imx95 — including the
   cross-build recipe and the practical issues of running it on the emulated target.

## Result

ORB-SLAM3 builds with effectively no porting work on the x86 baseline (zero source patches; 2 compiler
flags + 1 apt dep), converges on EuRoC MH_01, **and cross-builds headless and runs end-to-end on the
emulated i.MX 95 A55** — functional portability confirmed.

| | x86 baseline (i9-14900K P-core) | qemu-imx95 A55 (TCG) |
|---|---|---|
| Build | zero source patches (2 compiler flags + 1 apt dep) | headless cross-build (Pangolin/GL viewer removed) |
| median tracking / frame | **8.31 ms** (real-time), 6.52 ms (flat-out) | 178.5 ms *(emulation-dominated, not silicon)* |
| convergence (MH_01) | single map, 375 KFs, no track loss | single map (250-frame subset), converged |
| workload shape | CPU-only, latency/backend-bound, IPC ~1.5, ~24% LLC-miss, ~2 active cores, ~1 GB RSS | same; GPU/NPU never touched |

> The qemu-imx95 number is **TCG functional-emulation throughput, not i.MX 95 silicon performance** — it
> establishes *functional portability* to the A55 target class. Real-silicon timing would need hardware
> (or a cycle-accurate model).

## Repo layout

- [`phase0_orbslam3_inventory.md`](phase0_orbslam3_inventory.md) — the full, document-as-you-go build &
  characterization log (dependency install, every build fix, runtime + perf-stat numbers, workload
  characterization, surprises/blockers). **Start here for the detail.**
- `patches/` — source patches against upstream ORB-SLAM3 (pinned commit `4452a3c`):
  - `orbslam3-x86-instrumentation.patch` — per-frame tracking-time stats + a throttle-free
    `mono_euroc_flatout` variant (x86 baseline only; no functional changes).
  - `orbslam3-imx95-headless-crosscompile.patch` — headless build (removes the Pangolin/OpenGL viewer),
    `-mcpu=cortex-a55`, GLubyte stub, no-op Viewer, etc. — everything needed to cross-compile for the A55.
- [`CROSS_COMPILE_NOTES.md`](CROSS_COMPILE_NOTES.md) — reusable HOWTO for cross-building guest software
  for qemu-imx95 (sysroot setup, glibc skew + `--allow-shlib-undefined`, headless rationale, initramfs
  dependency-closure recipe, the SDHCI poweroff quirk).
- `harness/run_orbslam.sh` — x86 run harness (wall time, RSS, per-thread CPU, optional perf-stat).
- `qemu_work/`
  - `boot.sh` — non-modifying launch wrapper for qemu-imx95 (parameterizes INITRD + guest RAM).
  - `aarch64-toolchain.cmake` — CMake cross-toolchain (aarch64-linux-gnu + Yocto-rootfs sysroot).
  - `build_orbslam_initramfs.sh` — bakes the cross-built binary + lib dependency-closure + ORB vocab +
    a frame subset into a bootable initramfs (no virtio on this target → initramfs is the only way in).
- `results/` — captured run logs + perf-stat output.
- `setup_orbslam3.sh` — clones upstream ORB-SLAM3 at the pinned commit and applies the chosen patch.

Datasets, the cross sysroot, OpenCV source, vendored upstream trees and build artifacts are **not**
committed (large and reproducible) — see `.gitignore`. EuRoC MH_01 ships from the ETH Research
Collection (DOI 10.3929/ethz-b-000690084) as one 12.7 GB `machine_hall.zip` (the old per-sequence
`robotics.ethz.ch` URLs are dead); extract `machine_hall/MH_01_easy/MH_01_easy.zip` from it.

## Reproduce

**x86 baseline:** install deps (`libopencv-dev libeigen3-dev` + Pangolin v0.6 from source with
`-include cstdint`; `libboost-serialization-dev`), `./setup_orbslam3.sh x86`, build per the inventory
doc, then `harness/run_orbslam.sh`.

**qemu-imx95 A55:** `./setup_orbslam3.sh imx95`, cross-build the deps + ORB-SLAM3 against the Yocto
sysroot using `qemu_work/aarch64-toolchain.cmake` (see `CROSS_COMPILE_NOTES.md`),
`qemu_work/build_orbslam_initramfs.sh`, then
`MEM=8G INITRD=qemu_work/orbslam-initramfs.cpio.gz qemu_work/boot.sh`. Full step-by-step is in the
inventory doc.
