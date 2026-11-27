#!/bin/sh
# Copies the Atlas data from ../public (built by `make site`) into the app, so the app ships exactly what the website shows.
set -e
SRC="${SRCROOT}/../public"
DST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Atlas"
if [ ! -f "$SRC/places.json" ]; then echo "error: No Atlas data in public/. Run make site in the Appellation Atlas folder first."; exit 1; fi
mkdir -p "$DST"
rsync -a --delete --exclude '* [0-9].*' --exclude '* [0-9][0-9].*' --exclude '.DS_Store' "$SRC/places.json" "$SRC/compare.json" "$SRC/geo" "$SRC/facts" "$DST/"
