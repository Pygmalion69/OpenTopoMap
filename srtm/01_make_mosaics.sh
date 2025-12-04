#!/bin/bash
set -e

INPUT_DIR="unpacked"
OUT_DIR="mosaics_geo"

mkdir -p "$OUT_DIR"

echo "=== Generating 10×10° geographic mosaics (skipping empty regions) ==="

# Latitude from -90 to +80
for LAT in $(seq -90 10 80); do
  LAT_END=$((LAT + 10))

  # Longitude from -180 to +170
  for LON in $(seq -180 10 170); do
    LON_END=$((LON + 10))

    # Region naming
    LAT_S=$(printf "%+03d" $LAT)
    LON_S=$(printf "%+04d" $LON)
    REGION="${LAT_S}_${LON_S}"

    MOSAIC="$OUT_DIR/region_${REGION}.tif"

    # Scan HGT tiles for this 10×10° area
    FILES=$(find "$INPUT_DIR" -maxdepth 1 -name "*.tif" \
      | awk -v lat=$LAT -v lat_end=$LAT_END -v lon=$LON -v lon_end=$LON_END '
        {
          fname = $0
          n = split(fname, A, "/")
          tile = A[n]

          # Match pattern N59W002.hgt.tif or n59w002.hgt.tif
          if (match(tile, /^[NnSs][0-9]{2}[EeWw][0-9]{3}/)) {
            NS = substr(tile, 1, 1)
            LATV = substr(tile, 2, 2) + 0
            EW = substr(tile, 4, 1)
            LONV = substr(tile, 5, 3) + 0

            # Convert to signed
            if (NS == "S" || NS == "s") LATV = -LATV
            if (EW == "W" || EW == "w") LONV = -LONV

            # HGT tile covers [LATV, LATV+1) × [LONV, LONV+1)
            if (LATV >= lat && LATV < lat_end &&
                LONV >= lon && LONV < lon_end) {
              print fname
            }
          }
        }')

    # Skip empty regions
    if [ -z "$FILES" ]; then
      echo "Skipping empty region $REGION"
      continue
    fi

    echo "Creating mosaic for region $REGION"

    gdal_merge.py -o "$MOSAIC" -of GTiff $FILES
  done
done

echo "=== DONE: Valid region mosaics created ==="

