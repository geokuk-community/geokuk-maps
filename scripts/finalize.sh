#!/usr/bin/env bash
# Verifies the draft release (every file in layers.json is an uploaded asset of the same size) and publishes it as the latest release.
# Published releases are immutable, so nothing is published when a check fails.
# Env: GH_TOKEN, GITHUB_REPOSITORY, TAG (optional; the only draft release layers-* is used by default), DRY_RUN=1 (check only).
set -euo pipefail
: "${GH_TOKEN:?}" "${GITHUB_REPOSITORY:?}"
R=$(cd "$(dirname "$0")/.." && pwd)
api() { gh api "$@"; }
work=$(mktemp -d)
api "repos/$GITHUB_REPOSITORY/releases?per_page=100" --paginate > "$work/releases.json"
read -r ID TAG < <(python3 "$R/scripts/finalize-check.py" release "$work/releases.json" "${TAG:-}")
echo "Draft release $TAG ($ID)"
api "repos/$GITHUB_REPOSITORY/releases/$ID/assets" --paginate > "$work/assets.json"
aid=$(python3 "$R/scripts/finalize-check.py" asset-id "$work/assets.json" layers.json)
api -H "Accept: application/octet-stream" "repos/$GITHUB_REPOSITORY/releases/assets/$aid" > "$work/layers.json"
python3 "$R/scripts/finalize-check.py" verify "$work/layers.json" "$work/assets.json" "$TAG"
# Dem and contours kept from older releases (mapping/dem-manifest.json): those releases must still hold the files.
mkdir -p "$work/other"
cp "$work/releases.json" "$work/other/releases.json"
others=$(python3 "$R/scripts/finalize-check.py" other-tags "$work/layers.json" "$TAG")
for other in $others; do
  oid=$(python3 -c 'import json,sys; print(next(r["id"] for r in json.load(open(sys.argv[1])) if r["tag_name"] == sys.argv[2]))' "$work/releases.json" "$other") \
    || { echo "Release $other, which layers.json points to, does not exist" >&2; exit 1; }
  api "repos/$GITHUB_REPOSITORY/releases/$oid/assets" --paginate > "$work/other/$other.assets.json"
done
python3 "$R/scripts/finalize-check.py" verify-other "$work/layers.json" "$TAG" "$work/other"
python3 "$R/scripts/dem-source.py" check "$work/layers.json" "$TAG"
if [ "${DRY_RUN:-}" = 1 ]; then
  echo "Dry run: all checks passed, the release was not published"
  exit 0
fi
api -X PATCH "repos/$GITHUB_REPOSITORY/releases/$ID" -F draft=false -F make_latest=true > /dev/null
echo "Release $TAG published"
