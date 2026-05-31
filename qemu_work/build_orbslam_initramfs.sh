#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# ORB-SLAM3 i.MX95 port (Step 2) — assemble an initramfs that runs ORB-SLAM3 headless in qemu-imx95.
# Base = the booting glibc trim rootfs; add the cross-built binary + libs + dep-closure
# (pulled from the full Yocto rootfs) + ORB vocab + EuRoC.yaml + timestamps + frame subset.
# Custom /init runs mono_euroc on the subset, prints stats, powers off. Non-modifying (all under qemu_work).
set -eu
QW=~/Documents/GitHub/orbslam3-imx95/qemu_work
XW="$QW/orbslam3-cross"
FULL=~/Documents/qemu-imx95-artifacts/rootfs23/full
TRIM_CPIO=~/Documents/qemu-imx95-artifacts/rootfs23/trim.cpio.gz
OCVLIB="$QW/cross_build/opencv-install/lib"
BOOSTLIB="$QW/boost_1_74_0/stage/lib"
BUILD="$QW/initramfs_build"
NFRAMES="${NFRAMES:-250}"
OBJ=aarch64-linux-gnu-objdump

rm -rf "$BUILD"; mkdir -p "$BUILD"
echo "[1] unpack trim base"; ( cd "$BUILD" && zcat "$TRIM_CPIO" | cpio -idm 2>/dev/null )
mkdir -p "$BUILD/opt/orbslam/bin" "$BUILD/opt/orbslam/lib" "$BUILD/opt/orbslam/data"

echo "[2] copy cross-built binary + my libs"
cp "$XW/Examples/Monocular/mono_euroc" "$BUILD/opt/orbslam/bin/"
cp -a "$XW/lib/libORB_SLAM3.so" "$BUILD/opt/orbslam/lib/"
cp -a "$XW/Thirdparty/DBoW2/lib/libDBoW2.so" "$BUILD/opt/orbslam/lib/"
cp -a "$XW/Thirdparty/g2o/lib/libg2o.so" "$BUILD/opt/orbslam/lib/"
cp -a "$OCVLIB"/libopencv_*.so* "$BUILD/opt/orbslam/lib/"
cp -a "$BOOSTLIB"/libboost_serialization.so* "$BUILD/opt/orbslam/lib/"

echo "[3] dependency-closure: pull any missing NEEDED from full rootfs into /usr/lib"
# index of libs already available (trim usr/lib + my opt/orbslam/lib)
have() { find "$BUILD/usr/lib" "$BUILD/lib" "$BUILD/opt/orbslam/lib" -name "$1" 2>/dev/null | grep -q . ; }
# find a lib by soname under full rootfs
findfull() { find "$FULL" -name "$1" 2>/dev/null | head -1; }
queue=$(for f in "$BUILD/opt/orbslam/bin/mono_euroc" "$BUILD/opt/orbslam/lib/"*.so*; do
          $OBJ -p "$f" 2>/dev/null | awk '/NEEDED/{print $2}'; done | sort -u)
processed=""
while [ -n "$queue" ]; do
  next=""
  for so in $queue; do
    case " $processed " in *" $so "*) continue;; esac
    processed="$processed $so"
    if have "$so"; then continue; fi
    src=$(findfull "$so")
    if [ -n "$src" ]; then
      cp -aL "$src" "$BUILD/usr/lib/" && echo "    + $so  (from full rootfs)"
      next="$next $($OBJ -p "$src" 2>/dev/null | awk '/NEEDED/{print $2}')"
    else
      echo "    ! MISSING (not in trim or full): $so"
    fi
  done
  queue=$(echo "$next" | tr ' ' '\n' | sort -u)
done

echo "[4] data: vocab + yaml + timestamps + $NFRAMES-frame subset"
cp "$XW/Vocabulary/ORBvoc.txt" "$BUILD/opt/orbslam/data/"
cp "$XW/Examples/Monocular/EuRoC.yaml" "$BUILD/opt/orbslam/data/"
head -$NFRAMES "$XW/Examples/Monocular/EuRoC_TimeStamps/MH01.txt" > "$BUILD/opt/orbslam/data/MH01_times.txt"
mkdir -p "$BUILD/opt/orbslam/data/MH_01/mav0/cam0/data"
SRC=~/Documents/GitHub/orbslam3-imx95/datasets/MH_01/mav0/cam0/data
ls "$SRC" | head -$NFRAMES | while read f; do cp "$SRC/$f" "$BUILD/opt/orbslam/data/MH_01/mav0/cam0/data/"; done

echo "[5] custom /init"
cat > "$BUILD/init" <<'INIT'
#!/bin/bash
export PATH=/usr/bin:/usr/sbin TERM=linux
export LD_LIBRARY_PATH=/opt/orbslam/lib:/usr/lib
mount -t proc proc /proc; mount -t sysfs sysfs /sys
mount -t devtmpfs dev /dev 2>/dev/null; mount -t tmpfs tmpfs /tmp
echo "=== ORB-SLAM3 headless on imx95 (A55, TCG) ==="
echo "cores: $(grep -c ^processor /proc/cpuinfo)"; free -h | awk '/Mem/{print "RAM: "$2" total, "$7" avail"}'
D=/opt/orbslam/data
echo "frames: $(ls $D/MH_01/mav0/cam0/data/*.png 2>/dev/null | wc -l)"
echo "--- ldd mono_euroc ---"; LD_TRACE_LOADED_OBJECTS=1 /opt/orbslam/bin/mono_euroc 2>&1 | grep -iE "not found" && echo "  (missing libs above!)" || echo "  all libs resolved"
echo "=== RUN (wall-clock timed) ==="
cd /tmp
T0=$(cut -d' ' -f1 /proc/uptime)
/opt/orbslam/bin/mono_euroc $D/ORBvoc.txt $D/EuRoC.yaml $D/MH_01 $D/MH01_times.txt 2>&1
RC=$?
T1=$(cut -d' ' -f1 /proc/uptime)
echo "=== mono_euroc exit=$RC  wall=$(echo "$T1 - $T0" | bc 2>/dev/null || awk "BEGIN{print $T1-$T0}")s ==="
echo "=== DONE — powering off ==="
poweroff -f 2>/dev/null; sleep 2; exec bash
INIT
chmod +x "$BUILD/init"

echo "[6] repack cpio.gz"
OUT="$QW/orbslam-initramfs.cpio.gz"
( cd "$BUILD" && find . | cpio -o -H newc 2>/dev/null | gzip -1 > "$OUT" )
echo "[done] $OUT  ($(du -h "$OUT" | cut -f1))"
