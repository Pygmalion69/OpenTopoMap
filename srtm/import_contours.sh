#!/bin/sh

for f in contours/region_*.osm.pbf; do
  echo "Importing $f ..."
  osm2pgsql \
    --slim \
    --flat-nodes /tmp/flatnodes-contours.bin \
    -d contours \
    --cache 5000 \
    --style ~/OpenTopoMap/mapnik/osm2pgsql/contours.style \
    "$f"
done
