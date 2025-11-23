#!/bin/bash
set -e

########################################
# CONFIGURATION
########################################

RAW="raw.tif"
LOGDIR="$HOME/warp-logs"
SCREENDIR="$HOME/.screen_sessions"
RESOLUTIONS=("5000" "1000" "700" "500" "90")

THREADS="ALL_CPUS"
TILED="-co TILED=YES -co BLOCKXSIZE=256 -co BLOCKYSIZE=256"
COMP="-co COMPRESS=ZSTD"
BIGTIFF="-co BIGTIFF=YES"
WARP_OPTS="-multi --config GDAL_NUM_THREADS $THREADS -co NUM_THREADS=$THREADS"

# Web Mercator (spherical) target projection
TARGET_SRS='+proj=merc +ellps=sphere +R=6378137 +a=6378137 +units=m'

########################################
# PREPARE DIRECTORIES
########################################

mkdir -p "$LOGDIR"
mkdir -p "$SCREENDIR"

########################################
# CHECK RAW FILE
########################################

if [ ! -f "$RAW" ]; then
    echo "ERROR: $RAW not found in current directory."
    exit 1
fi

########################################
# DISK SPACE CHECK
########################################

REQUIRED_GB=200
FREE_GB=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')

if [ "$FREE_GB" -lt "$REQUIRED_GB" ]; then
    echo "WARNING: Only $FREE_GB GB free. Recommended: $REQUIRED_GB GB."
    echo "Warp may fail if insufficient space."
fi

########################################
# START SCREEN SESSIONS FOR EACH RESOLUTION
########################################

for RES in "${RESOLUTIONS[@]}"; do
    OUT="warp-$RES.tif"
    SESSION="warp_$RES"
    LOGFILE="$LOGDIR/warp-$RES.log"

    if screen -ls | grep -E "\.${SESSION}[[:space:]]" >/dev/null 2>&1; then
        echo "Skipping $RES (screen session already running)."
        continue
    fi

    if [ -f "$OUT" ]; then
        echo "Skipping $RES (output already exists)."
        continue
    fi

    echo "Starting warp for ${RES}m as screen session: $SESSION"
    echo "Log file: $LOGFILE"

    # Build the warp command
    CMD="gdalwarp $WARP_OPTS \
         $BIGTIFF $TILED $COMP \
         -t_srs \"$TARGET_SRS\" \
         -r bilinear \
         -tr $RES $RES \
         $RAW $OUT"

    # Write command to log
    echo "Running: $CMD" > "$LOGFILE"
    echo "" >> "$LOGFILE"

    # Launch inside screen
    screen -dmS "$SESSION" bash -c "$CMD >> \"$LOGFILE\" 2>&1"
done

########################################
# SUMMARY
########################################

echo
echo "All warp jobs started in screen sessions."
echo "Use 'screen -ls' to view running sessions."
echo "Use 'screen -r warp_5000' (etc) to attach."
echo "Logs are stored in: $LOGDIR"
echo "Output files will be created as warp-XXXX.tif"
echo
echo "Done."

