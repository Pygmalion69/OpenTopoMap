#!/usr/bin/env bash
set -euo pipefail

# ---------------- CONFIG ----------------
BATCH_SIZE=6

LIST_FILE="$HOME/srtm/list.txt"
BATCH_DIR="$HOME/srtm/batches"
CHECKPOINT_DIR="$HOME/srtm/checkpoints"
WORK_ROOT="$HOME/srtm/work"

CONTOURS_DB="contours"
CONTOUR_INTERVAL=10

HGT_BATCH_SIZE=6

export GDAL_NUM_THREADS=ALL_CPUS
# ----------------------------------------

mkdir -p "$BATCH_DIR" "$CHECKPOINT_DIR" "$WORK_ROOT"

echo "Splitting URL list into batches of $BATCH_SIZE ..."
split -l "$BATCH_SIZE" -d --additional-suffix=.txt \
  "$LIST_FILE" "$BATCH_DIR/batch_"

echo "Starting DEM batch processing..."

for BATCH_FILE in "$BATCH_DIR"/batch_*.txt; do
  BATCH_NAME=$(basename "$BATCH_FILE" .txt)
  CHECKPOINT_FILE="$CHECKPOINT_DIR/$BATCH_NAME.done"
  WORK_DIR="$WORK_ROOT/$BATCH_NAME"

  # ---- CHECKPOINT ----
  if [[ -f "$CHECKPOINT_FILE" ]]; then
    echo "Skipping $BATCH_NAME (checkpoint exists)"
    continue
  fi

  echo
  echo "===================================================="
  echo "Processing $BATCH_NAME"
  echo "===================================================="

  rm -rf "$WORK_DIR"
  mkdir -p "$WORK_DIR"/{download,extract}

  # ---- 1) Download ZIPs ----
  echo "Downloading ZIPs..."
  while IFS= read -r URL; do
    [[ -z "$URL" ]] && continue
    [[ "$URL" =~ ^# ]] && continue

    FILE="$(basename "$URL")"
    echo "  -> $FILE"
    wget -q --show-progress -O "$WORK_DIR/download/$FILE" "$URL"
  done < "$BATCH_FILE"

  # ---- 2) Extract ZIPs ----
  echo "Extracting ZIPs..."
  for ZIP in "$WORK_DIR"/download/*.zip; do
    unzip -q "$ZIP" -d "$WORK_DIR/extract"
  done

  # ---- 3) Collect HGT tiles ----
  mapfile -t ALL_HGTS < <(find "$WORK_DIR/extract" -type f -iname "*.hgt" | sort)

  if (( ${#ALL_HGTS[@]} == 0 )); then
    echo "ERROR: No HGT files found in $BATCH_NAME"
    exit 1
  fi

  echo "Found ${#ALL_HGTS[@]} HGT tiles"

  # ---- 4) Split into small geographic HGT batches ----
  HGT_BATCH_DIR="$WORK_DIR/hgt_batches"
  mkdir -p "$HGT_BATCH_DIR"

  printf "%s\n" "${ALL_HGTS[@]}" | \
    split -l "$HGT_BATCH_SIZE" -d --additional-suffix=.txt - \
    "$HGT_BATCH_DIR/hgt_batch_"

  # ---- 5) Process each HGT batch ----
  for HGT_BATCH in "$HGT_BATCH_DIR"/hgt_batch_*.txt; do
    SUB_NAME=$(basename "$HGT_BATCH" .txt)
    SUB_DIR="$WORK_DIR/sub_$SUB_NAME"

    echo "Processing HGT batch $SUB_NAME"

    mkdir -p "$SUB_DIR"/{tif,pbf}

    # -- Fill voids --
    idx=0
    while read -r HGT; do
      idx=$((idx + 1))
      gdal_fillnodata.py \
        "$HGT" \
        "$SUB_DIR/tif/tile_${idx}.tif"
    done < "$HGT_BATCH"

    # -- Mosaic --
    gdal_merge.py \
      -o "$SUB_DIR/raw.tif" \
      "$SUB_DIR"/tif/*.tif

    # -- Reproject --
    gdalwarp -multi \
      --config GDAL_NUM_THREADS ALL_CPUS \
      -co NUM_THREADS=ALL_CPUS \
      -co BIGTIFF=YES -co TILED=YES \
      -co BLOCKXSIZE=256 -co BLOCKYSIZE=256 \
      -co COMPRESS=ZSTD \
      -t_srs "+proj=merc +ellps=sphere +R=6378137 +a=6378137 +units=m" \
      -r bilinear -tr 90 90 \
      "$SUB_DIR/raw.tif" \
      "$SUB_DIR/warp-90.tif"

    # -- Contours --
    pyhgtmap \
      -s "$CONTOUR_INTERVAL" \
      -0 \
      --max-nodes-per-tile=0 \
      --pbf \
      -o "$SUB_DIR/pbf/contours" \
      "$SUB_DIR/warp-90.tif"

    # -- Import --
    osm2pgsql \
      --slim \
      --drop \
      -d "$CONTOURS_DB" \
      "$SUB_DIR"/pbf/contours*.pbf

    rm -rf "$SUB_DIR"
  done

  # ---- CHECKPOINT COMMIT ----
  touch "$CHECKPOINT_FILE"
  echo "Checkpoint written: $CHECKPOINT_FILE"

  # ---- Cleanup batch workspace ----
  rm -rf "$WORK_DIR"

done

echo
echo "All DEM batches processed successfully."

