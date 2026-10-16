#!/usr/bin/env bash
# Uploads the built files into the release layers-YYYY-MM and merges layers.json.
# Env: GH_TOKEN, GITHUB_REPOSITORY, MODE (draft|release), REGION, DIR (files to upload: *.map, *.dem.zip, *.poly, layers.json), TAG (optional).
set -euo pipefail
: "${GH_TOKEN:?}" "${GITHUB_REPOSITORY:?}" "${MODE:?}" "${DIR:?}"
R=$(cd "$(dirname "$0")/.." && pwd)
TAG=${TAG:-layers-$(date -u +%Y-%m)}
api() { gh api "$@"; }
ID=$(api "repos/$GITHUB_REPOSITORY/releases?per_page=100" --paginate --jq ".[]|select(.tag_name==\"$TAG\")|.id" | head -1)
if [ -z "$ID" ]; then
  ID=$(api -X POST "repos/$GITHUB_REPOSITORY/releases" -f tag_name="$TAG" -f name="Layers $TAG" -F draft=true \
    -f body="Offline map layers for GeoKuk (routes, contours, elevation data). See README.md and layers.json." --jq .id)
  echo "Created draft release $TAG ($ID)"
fi
mkdir -p "$DIR/existing"
asset_id() { api "repos/$GITHUB_REPOSITORY/releases/$ID/assets" --paginate --jq ".[]|select(.name==\"$1\")|.id" | head -1; }
download_catalog() { # $1 release id
  aid=$(api "repos/$GITHUB_REPOSITORY/releases/$1/assets" --paginate --jq '.[]|select(.name=="layers.json")|.id' | head -1)
  [ -n "$aid" ] && api -H "Accept: application/octet-stream" "repos/$GITHUB_REPOSITORY/releases/assets/$aid" > "$DIR/existing/layers.json" || return 1
}
if ! download_catalog "$ID"; then
  latest=$(api "repos/$GITHUB_REPOSITORY/releases/latest" --jq .id 2>/dev/null || true)
  [ -n "$latest" ] && download_catalog "$latest" || true
fi
if [ -s "$DIR/existing/layers.json" ]; then
  python3 "$R/scripts/merge-catalog.py" "$DIR/existing/layers.json" "$DIR/layers.json" "$DIR/layers.merged.json"
  mv "$DIR/layers.merged.json" "$DIR/layers.json"
fi
cat "$R/licenses/OSM.txt" > "$DIR/LICENSES.txt"; printf '\n\n' >> "$DIR/LICENSES.txt"; cat "$R/licenses/COPERNICUS.txt" >> "$DIR/LICENSES.txt"
for f in "$DIR"/*.map "$DIR"/*.dem.zip "$DIR"/*.poly "$DIR"/LICENSES.txt "$DIR"/layers.json; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  old=$(asset_id "$name" || true)
  [ -z "$old" ] || api -X DELETE "repos/$GITHUB_REPOSITORY/releases/assets/$old"
  curl -fsS -X POST -H "Authorization: Bearer $GH_TOKEN" -H "Content-Type: application/octet-stream" \
    --data-binary "@$f" "https://uploads.github.com/repos/$GITHUB_REPOSITORY/releases/$ID/assets?name=$name" > /dev/null
  echo "uploaded $name"
done
if [ "$MODE" = release ]; then
  api -X PATCH "repos/$GITHUB_REPOSITORY/releases/$ID" -F draft=false -F make_latest=true > /dev/null
  echo "Release $TAG published"
fi
