#!/bin/sh
set -e

IN_DIR="mosaics_merc"
OUT_DIR="contours"

mkdir -p "$OUT_DIR"

echo "=== Generating contours with pyhgtmap (final stable edition) ==="

for f in "$IN_DIR"/region_*_merc_90.tif; do
    base=$(basename "$f" .tif)
    region=${base%_merc_90}

    # canonical output naming:
    PBF="$OUT_DIR/$region.osm.pbf"

    echo ""
    echo "--- Processing $region ---"

    #########################################################
    # LAT CUT: skip >= 70°
    #########################################################
    LATPART=$(echo "$region" | awk -F_ '{print $2}')
    LONPART=$(echo "$region" | awk -F_ '{print $3}')

    # Normalize latitude
    LAT=${LATPART#+}
    LAT=${LAT#0}
    ABSLAT=${LAT#-}

    # Normalize longitude safely
    LON=$(echo "$LONPART" | sed 's/^+//')
    LON=$(echo "$LON" | sed 's/^\(-\?\)0*/\1/')

    if [ "$ABSLAT" -ge 70 ]; then
        echo " → Skipping $region (lat >= 70°)"
        continue
    fi

    #########################################################
    # SKIP ANY WORLD-EDGE LONGITUDE REGION
    # (this prevents all 445k-wide rasters)
    #########################################################

    if [ "$LON" -ge 170 ] || [ "$LON" -le -170 ]; then
        echo " → Skipping $region (|lon| >= 170°, full-width Mercator tile)"
        continue
    fi

    # Redundant explicit check (optional)
    if [ "$LON" -eq 180 ] || [ "$LON" -eq -180 ]; then
        echo " → Skipping $region (lon == ±180°)"
        continue
    fi

    #########################################################
    # Skip tile if existing PBF is valid
    #########################################################
    if [ -f "$PBF" ]; then
        SIZE=$(stat -c%s "$PBF" 2>/dev/null || echo 0)
        if [ "$SIZE" -gt 1024 ]; then
            echo " → Skipping $region (existing output, $SIZE bytes)"
            continue
        fi
        echo " → Removing partial file ($SIZE bytes)"
        rm -f "$PBF"
    fi

    #########################################################
    # Quick empty check
    #########################################################
    FILESIZE=$(stat -c%s "$f")
    if [ "$FILESIZE" -lt 10000000 ]; then
        echo " → Skipping $region (warp too small: $FILESIZE bytes)"
        continue
    fi

    #########################################################
    # Sample center 100×100 pixels
    #########################################################
    SIZE=$(gdalinfo "$f" | grep "Size is" | sed 's/.*Size is //;s/,/ /')
    WIDTH=$(echo "$SIZE" | awk '{print $1}')
    HEIGHT=$(echo "$SIZE" | awk '{print $2}')
    X=$((WIDTH/2))
    Y=$((HEIGHT/2))

    SAMPLE="/tmp/sample_${region}.tif"
    gdal_translate -srcwin "$X" "$Y" 100 100 "$f" "$SAMPLE" -q || {
        echo " → Skipping $region (sample read error)"
        rm -f "$SAMPLE"
        continue
    }

    SAMPLE_MIN=$(gdalinfo -stats "$SAMPLE" | grep "Minimum=" | sed 's/.*Minimum=//;s/,.*//')
    rm -f "$SAMPLE"

    case "$SAMPLE_MIN" in
        nan|-32768|3.40282e+38|0)
            echo " → Skipping $region (center has no elevation data)"
            continue
            ;;
    esac

    #########################################################
    # Run pyhgtmap
    #########################################################
    echo " → Running pyhgtmap (lat=$LATPART) ..."
    pyhgtmap \
      -s 10 \
      -0 \
      --max-nodes-per-tile=0 \
      --pbf \
      -o "$OUT_DIR/$region" \
      "$f"

    #########################################################
    # Rename extended pyhgtmap PBF to our canonical name
    #########################################################
    # pyhgtmap outputs something like:
    #  region_+60_+170_lon...lat....osm.pbf
    FOUND=$(ls "$OUT_DIR/${region}"*.osm.pbf 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        mv "$FOUND" "$PBF"
        echo " → Saved: $PBF"
    else
        echo " !!! ERROR: No PBF produced for $region"
    fi
done

echo ""
echo "=== DONE: Valid contour tiles generated ==="

