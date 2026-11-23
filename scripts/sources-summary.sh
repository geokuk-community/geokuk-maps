#!/usr/bin/env bash
# Writes OUT/summary.md (table in Czech) from OUT/results.tsv of scripts/sources-check.sh. When OUT/done is missing (the check step
# timed out or stopped), it first adds the row "kontrola nedoběhla", which counts as an outage. It writes only the file;
# scripts/sources-issue.sh adds the table to the run summary. Env: OUT.
set -euo pipefail
: "${OUT:?}"
results="$OUT/results.tsv"
mkdir -p "$OUT"
touch "$results"
if [ ! -e "$OUT/done" ]; then
  if ! grep -q $'^kontrola nedoběhla\t' "$results"; then
    printf 'kontrola nedoběhla\t-\tfail\t0\tkrok kontroly skončil dřív, než prošly všechny zdroje (timeout nebo chyba), dokončeno kontrol: %d\n' \
      "$(wc -l < "$results")" >> "$results"
  fi
fi
failed=$(awk -F'\t' '$3 == "fail"' "$results" | wc -l)
warned=$(awk -F'\t' '$3 == "warn"' "$results" | wc -l)
total=$(wc -l < "$results")
{
  echo "### Dostupnost zdrojů map"
  echo
  echo "Dostupné: $((total - failed - warned)) z $total, nedostupné: $failed, varování: $warned (Geofabrik je jen záložní zdroj, zkouší se jednou a výpadek neohlašuje)."
  echo
  echo "| Zdroj | URL | Stav | Čas | Podrobnosti |"
  echo "|---|---|---|---|---|"
  awk -F'\t' '{printf "| %s | %s | %s | %s ms | %s |\n", $1, $2, ($3 == "ok" ? "dostupný" : ($3 == "warn" ? "varování: nedostupný" : "**nedostupný**")), $4, $5}' "$results"
} > "$OUT/summary.md"
echo "$((total - failed - warned)) of $total sources available, $failed unavailable, $warned warnings"
awk -F'\t' '$3 == "warn" {printf "::warning::%s unavailable: %s\n", $1, $5}' "$results"
