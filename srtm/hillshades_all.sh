#!/bin/bash
set -e

########################################
# CONFIGURATION
########################################

LOGDIR="$HOME/hillshade-logs"
THREADS="ALL_CPUS"

# Each resolution has its own z-factor
#   RES  Z
declare -A ZFACTORS
ZFACTORS=(
  [5000]=7
  [1000]=7
  [700]=4
  [500]=4
  [90]=2
  [30m]=5   # special variant generated from warp-90
)

# List of products to generate:
HILLSHADES=("5000" "1000" "700" "500" "90" "30m")

# Common GDAL options
TILED="-co TILED=YES -co BLOCKXSIZE=256 -co BLOCKYSIZE=256"
BIGTIFF="-co BIGTIFF=YES"
COMP="-co COMPRESS=JPEG"
OPTS="--config GDAL_NUM_THREADS $THREADS -co NUM_THREADS=$THREADS"

########################################
# PREPARE
########################################

mkdir -p "$LOGDIR"

########################################
# FUNCTION TO CHECK EXACT SCREEN SESSION
########################################

screen_running_exact() {
    local session="$1"
    # Only match ".session " exactly, not substrings
    screen -ls | grep -E "\\.${session}[[:space:]]" >/dev/null 2>&1
}

########################################
# PROCESS EACH HILLSHADE TARGET
########################################

for RES in "${HILLSHADES[@]}"; do

    if [[ "$RES" == "30m" ]]; then
        SRC="warp-90.tif"
        OUT="hillshade-30m-jpeg.tif"
        Z="${ZFACTORS[30m]}"
        SESSION="hill_30m"
    else
        SRC="warp-$RES.tif"
        OUT="hillshade-$RES.tif"
        Z="${ZFACTORS[$RES]}"
        SESSION="hill_$RES"
    fi

    LOGFILE="$LOGDIR/hillshade-$RES.log"

    # Skip missing source
    if [ ! -f "$SRC" ]; then
        echo "Skipping $RES (source $SRC not found)"
        continue
    fi

    # Skip already completed outputs
    if [ -f "$OUT" ]; then
        echo "Skipping $RES ($OUT already exists)"
        continue
    fi

    # Skip if screen session is already running
    if screen_running_exact "$SESSION"; then
        echo "Skipping $RES (screen session already running)"
        continue
    fi

    echo "Starting hillshade for ${RES}m (z=$Z) in session: $SESSION"
    echo "Log: $LOGFILE"

    # Build GDAL command
    CMD="gdaldem hillshade \
         -z $Z \
         -compute_edges \
         $OPTS \
         $BIGTIFF $TILED $COMP \
         $SRC $OUT"

    # Write header to log
    echo "Running: $CMD" > "$LOGFILE"
    echo "" >> "$LOGFILE"

    # Start in detached screen session
    screen -dmS "$SESSION" bash -c "$CMD >> \"$LOGFILE\" 2>&1"
done

########################################
# SUMMARY
########################################

echo
echo "All hillshade jobs launched (where needed)."
echo "Logs in: $LOGDIR"
echo "Attach to jobs: screen -r hill_5000, hill_1000, hill_700, hill_500, hill_90, hill_30m"
echo

