#!/usr/bin/env bash
# Refreshes the region outlines in mapping/poly/<key>.poly from the mapsforge mirror (maps/poly/<key>.poly), one file at a time.
# The layers must cover the same area as the mapsforge base map, so the outlines come from mapsforge, not from Geofabrik.
# Usage: update-poly.sh [key ...]; without keys, all outlines already in mapping/poly are refreshed.
# Run by the workflow Region outlines (.github/workflows/poly.yml), which proposes the changes as a pull request.
# Env: MAPSFORGE_MIRROR (default the Hochschule Esslingen mirror), POLY_DELAY (seconds between downloads, default 2).
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
R=$(dirname "$D")
P="$R/mapping/poly"
MIRROR=${MAPSFORGE_MIRROR:-https://ftp-stud.hs-esslingen.de/pub/Mirrors/download.mapsforge.org}
keys=("$@")
if [ ${#keys[@]} -eq 0 ]; then
  mapfile -t keys < <(cd "$P" && find . -name '*.poly' | sed 's|^\./||; s|\.poly$||' | sort)
fi
[ ${#keys[@]} -gt 0 ] || { echo "No keys" >&2; exit 2; }
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
missing=()
changed=0
for key in "${keys[@]}"; do
  [[ "$key" =~ ^[a-z0-9-]+(/[a-z0-9-]+)*$ ]] || { echo "Invalid key: $key" >&2; exit 2; }
  if ! curl -fsS --retry 3 --retry-delay 10 --connect-timeout 30 -o "$tmp" "$MIRROR/maps/poly/$key.poly"; then
    missing+=("$key")
  elif [ "$(tail -n 1 "$tmp" | tr -d '[:space:]')" != END ] || ! python3 "$D/region-info.py" "$tmp" > /dev/null; then
    echo "Not a polygon file: $MIRROR/maps/poly/$key.poly" >&2
    missing+=("$key")
  elif ! cmp -s "$tmp" "$P/$key.poly"; then
    mkdir -p "$(dirname "$P/$key.poly")"
    cp "$tmp" "$P/$key.poly"
    echo "updated $key"
    changed=$((changed + 1))
  fi
  sleep "${POLY_DELAY:-2}"
done
echo "${#keys[@]} keys, $changed updated, ${#missing[@]} missing"
if [ ${#missing[@]} -gt 0 ]; then
  printf 'missing on the mirror: %s\n' "${missing[@]}" >&2
  exit 1
fi
