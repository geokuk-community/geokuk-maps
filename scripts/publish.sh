#!/usr/bin/env bash
# Uploads the built files into the release layers-YYYY-MM and merges layers.json.
# Env: GH_TOKEN, GITHUB_REPOSITORY, MODE (draft|release), DIR (one sub-folder per region with its files and layers.json), TAG (optional).
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
if [ "$MODE" = draft ] && [ "$(api "repos/$GITHUB_REPOSITORY/releases/$ID" --jq .draft)" != true ]; then
  echo "Release $TAG is already published; refusing to change it in draft mode" >&2
  exit 1
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
cur="$DIR/existing/layers.json"
for frag in "$DIR"/*/layers.json; do
  [ -f "$frag" ] && [ "$frag" != "$DIR/existing/layers.json" ] || continue
  if [ -s "$cur" ]; then
    python3 "$R/scripts/merge-catalog.py" "$cur" "$frag" "$DIR/merged.json"
    mv "$DIR/merged.json" "$DIR/layers.json"
  else
    cp "$frag" "$DIR/layers.json"
  fi
  cur="$DIR/layers.json"
done
cat "$R/licenses/OSM.txt" > "$DIR/LICENSES.txt"; printf '\n\n' >> "$DIR/LICENSES.txt"; cat "$R/licenses/COPERNICUS.txt" >> "$DIR/LICENSES.txt"
for f in "$DIR"/*/*.map "$DIR"/*/*.dem.zip "$DIR"/*/*.poly "$DIR"/LICENSES.txt "$DIR"/layers.json; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  size=$(stat -c %s "$f")
  for attempt in 1 2 3 4; do
    old=$(asset_id "$name" || true)
    [ -z "$old" ] || api -X DELETE "repos/$GITHUB_REPOSITORY/releases/assets/$old"
    curl -fsS --retry 3 --retry-all-errors -X POST -H "Authorization: Bearer $GH_TOKEN" -H "Content-Type: application/octet-stream" \
      --data-binary "@$f" "https://uploads.github.com/repos/$GITHUB_REPOSITORY/releases/$ID/assets?name=$name" > /dev/null || true
    got=$(api "repos/$GITHUB_REPOSITORY/releases/$ID/assets" --paginate --jq ".[]|select(.name==\"$name\" and .state==\"uploaded\")|.size" | head -1)
    [ "$got" = "$size" ] && break
    [ "$attempt" -lt 4 ] || { echo "Upload of $name failed" >&2; exit 1; }
  done
  echo "uploaded $name"
done
if [ "$MODE" = release ]; then
  api -X PATCH "repos/$GITHUB_REPOSITORY/releases/$ID" -F draft=false -F make_latest=true > /dev/null
  echo "Release $TAG published"
fi
