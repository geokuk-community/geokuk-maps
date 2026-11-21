#!/usr/bin/env bash
# Downloads the artifacts region-* of a Layers run one at a time into DIR/<artifact name>/ and checks the SHA-256 of each zip
# against the digest of the artifact. actions/download-artifact with run-id fetched all 132 region artifacts of a full run at
# once and hit the secondary rate limit of the GitHub API (run 44886196372, job publish), so this script downloads them in turn
# and waits and tries again when the API refuses a request.
# Env: GH_TOKEN, GITHUB_REPOSITORY, RUN (run id), DIR; optional PREFIX (default region-), DOWNLOAD_RETRY_DELAY (seconds, default 60).
set -euo pipefail
: "${GH_TOKEN:?}" "${GITHUB_REPOSITORY:?}" "${RUN:?}" "${DIR:?}"
PREFIX=${PREFIX:-region-}
[[ "$RUN" =~ ^[0-9]+$ ]] || { echo "RUN must be a run id" >&2; exit 2; }
delay=${DOWNLOAD_RETRY_DELAY:-60}
mkdir -p "$DIR"
list=$(mktemp)
zip=$(mktemp)
trap 'rm -f "$list" "$zip"' EXIT
gh api "repos/$GITHUB_REPOSITORY/actions/runs/$RUN/artifacts?per_page=100" --paginate \
  --jq ".artifacts[]|select(.name|startswith(\"$PREFIX\"))|select(.expired|not)|[.id, .name, .digest // \"\"]|@tsv" | sort -k2 > "$list"
total=$(wc -l < "$list")
[ "$total" -gt 0 ] || { echo "No artifact $PREFIX* in run $RUN" >&2; exit 1; }
echo "$total artifacts $PREFIX* in run $RUN"
n=0
while IFS=$'\t' read -r id name digest; do
  n=$((n + 1))
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid artifact name: $name" >&2; exit 1; }
  for try in 1 2 3 4 5; do
    if gh api "repos/$GITHUB_REPOSITORY/actions/artifacts/$id/zip" > "$zip"; then
      actual="sha256:$(sha256sum "$zip" | awk '{print $1}')"
      if [ -z "$digest" ] || [ "$actual" = "$digest" ]; then
        break
      fi
      echo "::warning::Digest of $name is $actual, expected $digest (attempt $try of 5)"
    else
      echo "::warning::Download of $name failed (attempt $try of 5)"
    fi
    [ "$try" -lt 5 ] || { echo "Download of $name failed" >&2; exit 1; }
    sleep $((try * delay))
  done
  rm -rf "${DIR:?}/$name"
  mkdir -p "$DIR/$name"
  unzip -q "$zip" -d "$DIR/$name"
  echo "$n/$total $name $(stat -c %s "$zip") bytes"
done < "$list"
