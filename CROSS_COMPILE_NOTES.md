# Cross-compiling guest software for qemu-imx95 (Yocto trim rootfs)

Practical notes for building a non-trivial C++ application on an x86 host and running it inside the
qemu-imx95 emulated i.MX 95 (Cortex-A55) Linux userspace. Distilled from porting ORB-SLAM3 (OpenCV +
g2o + DBoW2 + Sophus + boost-serialization). The same recipe should apply to any glibc-dynamic workload.

## TL;DR

1. Cross-compile on the host (native build on the TCG-emulated A55 is impractical for large C++).
2. Use the Yocto **full rootfs as the CMake sysroot**; reuse arch-independent headers (Eigen) from the host.
3. Target `-mcpu=cortex-a55`.
4. Build **headless** — the emulator has no GPU/GL, so strip any OpenGL/X11/Pangolin/viewer dependency.
5. Link with **`-Wl,--allow-shlib-undefined`** to absorb the glibc version skew (see below).
6. There is **no virtio / no block storage** — bake the binary + its shared-lib closure + data into the
   initramfs cpio. Size guest RAM (`-m`) to hold it all (initramfs is RAM-resident).

## The glibc skew (the one real gotcha)

- The Yocto **trim/full rootfs ships a modern glibc (2.41)** and a GCC-13-era `libstdc++.so.6.0.33`.
- Ubuntu 22.04's `aarch64-linux-gnu` cross toolchain ships **glibc 2.35** and GCC 11.
- Your own objects compiled with the 2.35 toolchain only emit `<=2.35` glibc symbols → they run fine on
  the target's newer glibc (**forward compatible**). `libstdc++` is likewise a non-issue: the newer
  target `.so` carries all older `GLIBCXX`/`CXXABI` symbol versions (**backward compatible**).
- The break appears when a **rootfs shared library you transitively link needs a newer glibc symbol than
  your toolchain knows**. Concretely: `libcrypto.so.3` (pulled in via OpenCV) references
  `__isoc23_strtol@GLIBC_2.38` (a C23 symbol emitted by GCC 13), which the 2.35 toolchain's libc can't
  resolve at link time → `undefined reference ... @GLIBC_2.38`.
- **Fix:** `-Wl,--allow-shlib-undefined`. This tells the linker not to error on symbols left undefined
  *inside shared libraries* — they resolve at runtime against the target's actual (2.41) glibc, which
  has them. It does **not** mask undefined symbols in your own objects.

```cmake
# in the link step (e.g. CMAKE_SHARED_LINKER_FLAGS / CMAKE_EXE_LINKER_FLAGS)
-Wl,--allow-shlib-undefined
```

## CMake cross-toolchain (sketch)

See `qemu_work/aarch64-toolchain.cmake` for the working file. Key points:

```cmake
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER   aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
set(CMAKE_SYSROOT      /path/to/rootfs23/full)   # the Yocto rootfs as sysroot
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)     # use host tools, target libs/headers
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
include_directories(SYSTEM /usr/include/eigen3)  # arch-independent headers from host are fine
set(CMAKE_CXX_FLAGS_INIT "-include cstdint")     # GCC-strictness helper for older C++ codebases
```

Notes:
- The Yocto rootfs is **runtime-only** (no `-dev` headers). For libraries where you need headers
  (e.g. OpenCV), either fetch the matching-version source headers or do a reduced cross-build of that
  library (we did a reduced OpenCV 4.12 cross-build → clean `OpenCVConfig.cmake` + headers + `.so`).
- Header-only deps (Eigen) just come from the host; arch doesn't matter.

## Headless build

The emulator has no GPU/DRM (Mali/DPU are probe-stubs, no `/dev/dri`, `vulkaninfo`/`kmscube` fail). Any
live OpenGL/X11 GUI cannot render. Build the application **viewer-less**: this also drops the entire GL
stack (libGL/GLEW/X11/Pangolin in our case) from both the build and the runtime closure. In ORB-SLAM3 the
viewer was cleanly separable (a few `#if 0` / stub edits) — budget similar surgery for other apps.

## Getting it into the guest (no virtio)

There is no virtio-blk and no working `/dev/mmcblk*` under Linux — the **initramfs is the only channel**.
Build a cpio that extends the base trim rootfs with:
- your binary,
- its **full shared-library dependency closure** (walk `NEEDED` with `objdump -p` / `readelf -d`,
  recursively; pull any missing `.so` from the full rootfs),
- data files,
- a custom `/init` that sets `LD_LIBRARY_PATH`, runs your program, and prints results.

It is all RAM-resident, so size guest memory accordingly: `-m` is **not** DTB-pinned (honored up to 16G,
default 8G). See `qemu_work/build_orbslam_initramfs.sh` for a working dependency-closure + pack script,
and `qemu_work/boot.sh` for the launch wrapper.

## Known quirk: poweroff hangs the VM

Guest `poweroff` does **not** terminate QEMU on this machine (the PSCI `SYSTEM_OFF` path doesn't reach
`qemu_system_shutdown`, and the uSDHC model loops dumping `mmc1: sdhci-esdhc-imx: ... debug status`).
Your workload finishes cleanly first — just **scrape the console output, then `SIGKILL` the QEMU PID**;
don't rely on `poweroff` to exit. (Reported to the qemu-imx95 maintainers; on their fix list.)
