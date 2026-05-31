#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# ORB-SLAM3 i.MX95 port — ORB-SLAM3 monocular EuRoC run harness
# Captures: wall time, Max RSS, overall CPU%, per-thread CPU (top -H), track-time stats (binary stderr),
#           and optionally perf stat (IPC, cache-misses, branch-misses) for the flat-out run.
#
# Usage: run_orbslam.sh <binary> <label> <seq_folder> <timestamps> [perf]
#   binary      : full path to mono_euroc or mono_euroc_flatout
#   label       : output name (results/<label>.*)
#   seq_folder  : folder containing mav0/  (e.g. .../MH_01)
#   timestamps  : EuRoC_TimeStamps/MH01.txt
#   perf        : literal "perf" to wrap in `perf stat -d -d` (needs perf_event_paranoid<=1)
set -u
ORB=~/Documents/GitHub/orbslam3-imx95/orbslam3/ORB_SLAM3
VOCAB="$ORB/Vocabulary/ORBvoc.txt"
YAML="$ORB/Examples/Monocular/EuRoC.yaml"
RES=~/Documents/GitHub/orbslam3-imx95/results
mkdir -p "$RES"

BIN="$1"; LABEL="$2"; SEQ="$3"; TS="$4"; USEPERF="${5:-}"
OUT="$RES/$LABEL"
echo "[harness] binary=$BIN label=$LABEL seq=$SEQ perf=$USEPERF"
echo "[harness] images: $(ls "$SEQ/mav0/cam0/data"/*.png 2>/dev/null | wc -l)"

# run from a per-label workdir so trajectory outputs don't collide
WORK="$RES/$LABEL.work"; mkdir -p "$WORK"; cd "$WORK"

CMD=(/usr/bin/time -v "$BIN" "$VOCAB" "$YAML" "$SEQ" "$TS")
if [ "$USEPERF" = "perf" ]; then
  CMD=(/usr/bin/time -v perf stat -d -d -o "$OUT.perf.txt" -- "$BIN" "$VOCAB" "$YAML" "$SEQ" "$TS")
fi

# launch in background to sample per-thread CPU
"${CMD[@]}" > "$OUT.stdout.log" 2> "$OUT.timeerr.log" &
HPID=$!
# find the actual mono_euroc pid (child of time/perf)
sleep 2
TARGET=$(pgrep -P "$HPID" -f mono_euroc 2>/dev/null | head -1)
[ -z "$TARGET" ] && TARGET=$(pgrep -f "$(basename "$BIN")" | head -1)
echo "[harness] harness pid=$HPID target pid=$TARGET"
# sample per-thread CPU every 1s while alive
( while kill -0 "$TARGET" 2>/dev/null; do
    top -H -b -n1 -p "$TARGET" 2>/dev/null | awk 'NR>7 && $9!="" {print $1, $9, $12}'
    echo "---tick---"
    sleep 1
  done ) > "$OUT.threads.log" 2>/dev/null &
SAMPLER=$!

wait "$HPID"; RC=$?
kill "$SAMPLER" 2>/dev/null
echo "[harness] run exit=$RC"
echo "[harness] outputs in $OUT.*  (workdir $WORK)"
