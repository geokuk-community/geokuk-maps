#!/usr/bin/env bash
# Copies the outline of a region (mapsforge key) from mapping/poly/<key>.poly, which scripts/update-poly.sh keeps in step with the
# mapsforge base maps. A key that is not in the repository yet is read from the mapsforge mirror, with a warning to add it.
# Usage: region-poly.sh key output.poly. Env: optional MAPSFORGE_MIRROR.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
R=$(dirname "$D")
key=$1 out=$2
[[ "$key" =~ ^[a-z0-9-]+(/[a-z0-9-]+)*$ ]] || { echo "Invalid key: $key" >&2; exit 2; }
mkdir -p "$(dirname "$out")"
if [ -s "$R/mapping/poly/$key.poly" ]; then
  cp "$R/mapping/poly/$key.poly" "$out"
  exit 0
fi
url="${MAPSFORGE_MIRROR:-https://ftp-stud.hs-esslingen.de/pub/Mirrors/download.mapsforge.org}/maps/poly/$key.poly"
echo "::warning::mapping/poly/$key.poly is not in the repository, reading $url (add it with scripts/update-poly.sh $key)"
curl -fsSL --retry 5 --retry-delay 20 --connect-timeout 30 -o "$out" "$url" \
  || { echo "No outline for $key ($url)" >&2; exit 1; }
