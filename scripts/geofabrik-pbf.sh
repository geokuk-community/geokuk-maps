#!/usr/bin/env bash
# Downloads the Geofabrik extract of a path and checks its MD5. The URL comes from the Geofabrik index (geofabrik-url.py);
# *-latest.osm.pbf redirects to a dated file, whose own .md5 is checked so that a new extract between the two downloads does not fail.
# Usage: geofabrik-pbf.sh path output.pbf [measure_step]. Env: WORK (the index is kept there), OUT (with a measure step);
# optional GEOFABRIK_INDEX (index file to use instead of downloading it), GEOFABRIK_RETRY_DELAY (seconds, default 60).
set -euo pipefail
: "${WORK:?}"
D=$(cd "$(dirname "$0")" && pwd)
key=$1 pbf=$2 step=${3:-}
index=${GEOFABRIK_INDEX:-$WORK/geofabrik-index.json}
if [ ! -s "$index" ]; then
  mkdir -p "$(dirname "$index")"
  curl -fsSL --retry 5 --retry-all-errors --retry-delay 20 --connect-timeout 30 -o "$index.tmp" https://download.geofabrik.de/index-v1-nogeom.json
  mv "$index.tmp" "$index"
fi
url=$(python3 "$D/geofabrik-url.py" "$index" "$key")
# *-latest.osm.pbf redirects to the dated file; that file was seen answering 404 for a while (2026-11-21), so a failed
# download is tried again after a pause, and the URL that failed is logged.
fetch() {
  local effective try
  for try in 1 2 3 4; do
    if effective=$(${step:+"$D/measure.sh" "$step"} curl -fL --retry 5 --retry-delay 10 --connect-timeout 30 -w '%{url_effective}' -o "$pbf" "$url"); then
      echo "Downloaded $effective"
      file_url=$effective
      return 0
    fi
    echo "::warning::Download of $url failed at ${effective:-$url} (attempt $try of 4)"
    [ "$try" -lt 4 ] && sleep $((try * ${GEOFABRIK_RETRY_DELAY:-60}))
  done
  echo "Download of $url failed" >&2
  return 1
}
fetch
for attempt in 1 2 3; do
  expected=""
  for try in 1 2 3 4 5 6; do
    for u in "$file_url.md5" "$url.md5"; do
      expected=$(curl -fsSL --connect-timeout 30 "$u" | awk '{print $1}') && [[ "$expected" =~ ^[0-9a-f]{32}$ ]] && break 2
      expected=""
    done
    sleep $((try * 20))
  done
  if [ -z "$expected" ]; then
    echo "::warning::Checksum of $file_url is not available; checking that the file can be read completely"
    osmium fileinfo -e "$pbf" > /dev/null && break
  elif [ "$(md5sum "$pbf" | awk '{print $1}')" = "$expected" ]; then
    break
  fi
  [ "$attempt" -lt 3 ] || { echo "Checksum mismatch for $file_url" >&2; exit 1; }
  sleep 60
  fetch
done
