#!/usr/bin/env bash
# Reports the result of scripts/sources-check.sh in an issue. On an outage it opens the issue "Nedostupné zdroje map: <list>" with the
# label LABEL, assigned to ASSIGNEE, or, when such an issue is already open, adds a comment with the new run. When every source is
# available again and an open issue exists, it adds the comment "Zdroje jsou znovu dostupné" once. It never closes the issue.
# Env: GH_TOKEN, GITHUB_REPOSITORY, OUT (with results.tsv and summary.md), RUN_URL; optional LABEL (default zdroje), ASSIGNEE, TEST_URL.
set -euo pipefail
: "${GH_TOKEN:?}" "${GITHUB_REPOSITORY:?}" "${OUT:?}" "${RUN_URL:?}"
LABEL=${LABEL:-zdroje}
TITLE="Nedostupné zdroje map"
results="$OUT/results.tsv"
[ -s "$results" ] || { echo "No results in $results" >&2; exit 1; }
if [ "$(gh api "repos/$GITHUB_REPOSITORY" --jq .has_issues)" != true ]; then
  echo "::error::Issues are disabled in $GITHUB_REPOSITORY (Settings, General, Features); the result is only in the run summary"
  exit 1
fi
failed=$(awk -F'\t' '$3 == "fail" {print $1}' "$results" | paste -sd ',' - | sed 's/,/, /g')
warn=$(awk -F'\t' '$3 == "warn" {print $1}' "$results" | paste -sd ',' - | sed 's/,/, /g')
gh label list --repo "$GITHUB_REPOSITORY" --limit 200 --json name --jq '.[].name' | grep -qxF "$LABEL" \
  || gh label create "$LABEL" --repo "$GITHUB_REPOSITORY" --color d93f0b --description "Dostupnost zdrojů map (workflow Sources check)"
issue=$(gh issue list --repo "$GITHUB_REPOSITORY" --label "$LABEL" --state open --limit 50 --json number,title \
  --jq "[.[] | select(.title | startswith(\"$TITLE\"))] | sort_by(.number) | .[0].number // empty")
body="$OUT/issue.md"
if [ -n "$failed" ]; then
  {
    echo "Kontrola dostupnosti zdrojů map našla nedostupné zdroje (každý zkoušen 3×): $failed."
    echo
    echo "Běh: $RUN_URL"
    [ -z "${TEST_URL:-}" ] || { echo; echo "Běh se zkušební adresou (vstup test_url): $TEST_URL"; }
    echo
    awk -F'\t' 'BEGIN {print "| Zdroj | URL | Podrobnosti |"; print "|---|---|---|"} $3 == "fail" {printf "| %s | %s | %s |\n", $1, $2, $5}' "$results"
    [ -z "$warn" ] || { echo; echo "Varování (záložní zdroj, samo issue nezakládá): $warn."; }
    echo
    echo "<details><summary>Všechny kontroly</summary>"
    echo
    tail -n +3 "$OUT/summary.md"
    echo
    echo "</details>"
  } > "$body"
  if [ -n "$issue" ]; then
    gh issue comment "$issue" --repo "$GITHUB_REPOSITORY" --body-file "$body"
    echo "Outage added to issue #$issue"
  else
    gh issue create --repo "$GITHUB_REPOSITORY" --title "$TITLE: $failed" --label "$LABEL" ${ASSIGNEE:+--assignee "$ASSIGNEE"} --body-file "$body"
  fi
elif [ -n "$issue" ]; then
  last=$(gh issue view "$issue" --repo "$GITHUB_REPOSITORY" --json comments --jq '.comments[-1].body // ""')
  if [[ "$last" == "Zdroje jsou znovu dostupné"* ]]; then
    echo "Issue #$issue already says that the sources are available again"
  else
    {
      if [ -n "$warn" ]; then
        echo "Zdroje jsou znovu dostupné (zůstává jen varování u záložního zdroje: $warn)."
      else
        echo "Zdroje jsou znovu dostupné (všechny kontroly prošly)."
      fi
      echo
      echo "Běh: $RUN_URL"
    } > "$body"
    gh issue comment "$issue" --repo "$GITHUB_REPOSITORY" --body-file "$body"
    echo "Recovery added to issue #$issue"
  fi
else
  echo "All sources available, no open issue"
fi
