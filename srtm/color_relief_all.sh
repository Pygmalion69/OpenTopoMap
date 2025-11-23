#!/bin/bash
set -e

RAW_COLORS="../OpenTopoMap/mapnik/relief_color_text_file.txt"
LOGDIR="$HOME/color-logs"
RESOLUTIONS=("5000" "500")
THREADS="ALL_CPUS"
TILED="-co TILED=YES -co BLOCKXSIZE=256 -co BLOCKYSIZE=256"
COMP="-co COMPRESS=ZSTD"
BIGTIFF="-co BIGTIFF=YES"
OPTS="--config GDAL_NUM_THREADS $THREADS -co NUM_THREADS=$THREADS"

mkdir -p "$LOGDIR"

for RES in "${RESOLUTIONS[@]}"; do
    SRC="warp-$RES.tif"
    OUT="relief-$RES.tif"
    SESSION="relief_$RES"
    LOGFILE="$LOGDIR/relief-$RES.log"

    if [ ! -f "$SRC" ]; then
        echo "Skipping $RES (source $SRC missing)"
        continue
    fi

    if [ -f "$OUT" ]; then
        echo "Skipping $RES ($OUT already exists)"
        continue
    fi

    if screen -ls | grep -E "\\.${SESSION}[[:space:]]" >/dev/null 2>&1; then
        echo "Skipping $RES (screen session already running)"
        continue
    fi

    echo "Starting color relief for ${RES}m in session: $SESSION"
    echo "Log: $LOGFILE"

    CMD="gdaldem color-relief $OPTS $BIGTIFF $TILED $COMP \
         $SRC $RAW_COLORS $OUT"

    echo "Running: $CMD" > "$LOGFILE"
    echo "" >> "$LOGFILE"

    screen -dmS "$SESSION" bash -c "$CMD >> \"$LOGFILE\" 2>&1"
done

echo
echo "Color relief jobs launched."
echo "Logs: $LOGDIR"
echo "Attach: screen -r relief_5000 (or relief_500)"
echo

