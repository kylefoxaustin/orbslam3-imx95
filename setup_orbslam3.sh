#!/usr/bin/env bash
# Clone upstream ORB-SLAM3 at the pinned commit and apply the appropriate patch.
# Usage: ./setup_orbslam3.sh [x86|imx95]   (default: x86)
#   x86   -> instrumentation only (per-frame stats + throttle-free flatout variant)
#   imx95 -> headless cross-compile patch (Pangolin removed, -mcpu=cortex-a55, etc.)
set -eu
PINNED=4452a3c4ab75b1cde34e5505a36ec3f9edcdc4c4   # ORB-SLAM3 upstream HEAD used for these notes (2026-05-30)
VARIANT="${1:-x86}"
DST="ORB_SLAM3-${VARIANT}"
HERE="$(cd "$(dirname "$0")" && pwd)"

case "$VARIANT" in
  x86)   PATCH="$HERE/patches/orbslam3-x86-instrumentation.patch" ;;
  imx95) PATCH="$HERE/patches/orbslam3-imx95-headless-crosscompile.patch" ;;
  *) echo "usage: $0 [x86|imx95]"; exit 1 ;;
esac

[ -d "$DST" ] && { echo "$DST already exists; remove it first"; exit 1; }
git clone https://github.com/UZ-SLAMLab/ORB_SLAM3.git "$DST"
( cd "$DST" && git checkout -q "$PINNED" 2>/dev/null || echo "note: pinned commit not in shallow history; using current master" )
echo "Applying $PATCH ..."
( cd "$DST" && patch -p1 < "$PATCH" )
echo "Done. ORB-SLAM3 ($VARIANT) ready in $DST/."
echo "Next: build Thirdparty (DBoW2/g2o/Sophus), extract Vocabulary/ORBvoc.txt.tar.gz, then build."
echo "See phase0_orbslam3_inventory.md for the full dependency + build recipe."
