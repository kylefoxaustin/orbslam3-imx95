#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# ORB-SLAM3 i.MX95 port (Step 2) — non-modifying launch wrapper for qemu-imx95.
# Uses the EXISTING built qemu binary (v1.x) read-only. Does not write into the repo.
# Replicates tests/swap-boot/run.sh's invocation with our own INITRD + RAM override.
set -u
REPO=~/Documents/GitHub/95emulator
ART=~/Documents/qemu-imx95-artifacts
QEMU="$REPO/build/qemu-system-aarch64"
SM_ELF="$HOME/Documents/nxp/sources/imx-sm/build/mx95evk/m33_image.elf"
KERNEL="$HOME/Documents/linux-imx95-build/arch/arm64/boot/Image"
DTB="$HOME/Documents/linux-imx95-build/arch/arm64/boot/dts/freescale/imx95-19x19-evk.dtb"
INITRD="${INITRD:-$ART/rootfs23/trim.cpio.gz}"
MEM="${MEM:-8G}"   # imx95 machine default is 8G (honors -m up to 16G; not DTB-pinned) — per 95emulator
CMDLINE="earlycon=lpuart32,mmio32,0x44380010 console=ttyLP0,115200 cpuidle.off=1 rdinit=/init"

exec "$QEMU" -M imx95-19x19-evk -m "$MEM" -display none \
    -kernel "$KERNEL" -dtb "$DTB" -initrd "$INITRD" \
    -append "$CMDLINE" \
    -device loader,file="$SM_ELF",cpu-num=6 \
    -serial mon:stdio -serial null \
    "$@"
