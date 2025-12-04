#!/bin/bash
set -e

IN_DIR="mosaics_geo"
OUT_DIR="mosaics_merc"

mkdir -p "$OUT_DIR"

echo "=== Reprojecting mosaics to Mercator (90m), skipping empty ones ==="

for f in $IN_DIR/region_*.tif; do
    base=$(basename "$f" .tif)
    out="$OUT_DIR/${base}_merc_90.tif"

    echo "Checking $base ..."

    # Extract minimum value; if it's "nan" or extremely high, it's empty
    MIN=$(gdalinfo -stats "$f" | grep "Minimum=" | sed 's/Minimum=//' | awk -F, '{print $1}')

    # Typical empty mosaic min values:
    # nan, -32768, 0, or 3.40282e+38 (float32 NODATA)
    if [[ "$MIN" == "nan" ]] || [[ "$MIN" == "0" ]] || [[ "$MIN" == "-32768" ]] || [[ "$MIN" == "3.40282e+38" ]]; then
        echo " → Skipping $base (empty mosaic)"
        continue
    fi

    echo " → Reprojecting $base ..."
    gdalwarp -multi \
      --config GDAL_NUM_THREADS ALL_CPUS \
      -co NUM_THREADS=ALL_CPUS \
      -co BIGTIFF=YES -co TILED=YES \
      -co BLOCKXSIZE=256 -co BLOCKYSIZE=256 \
      -co COMPRESS=ZSTD \
      -t_srs "+proj=merc +ellps=sphere +R=6378137 +a=6378137 +units=m" \
      -r bilinear -tr 90 90 \
      "$f" "$out"
done

echo "=== DONE: Valid mosaics reprojected ==="
