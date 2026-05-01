#!/usr/bin/env bash
# stats.sh — Print a summary of the Company Graph contents
# Usage: ./scripts/stats.sh
# Dependencies: jq (brew install jq)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRAPH_DIR="$REPO_ROOT/graph"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

header() { echo -e "\n${BLUE}${BOLD}$1${NC}"; echo -e "${BLUE}$(printf '─%.0s' {1..50})${NC}"; }
row() { printf "  %-38s %s\n" "$1" "$2"; }

echo ""
echo -e "${BOLD}${CYAN}  Company Graph — Veridian  |  $(date '+%Y-%m-%d')${NC}"
echo -e "${CYAN}  $(printf '═%.0s' {1..50})${NC}"

# ─────────────────────────────────────────────
# Entity Counts
# ─────────────────────────────────────────────
header "Entity Summary"

ACTOR_COUNT=$(jq '. | length' "$GRAPH_DIR/actors.json")
WORKFLOW_COUNT=$(jq '. | length' "$GRAPH_DIR/workflows.json")
DECISION_COUNT=$(jq '. | length' "$GRAPH_DIR/decisions.json")
COMMITMENT_COUNT=$(jq '. | length' "$GRAPH_DIR/commitments.json")
VALUE_OBJECT_COUNT=$(jq '. | length' "$GRAPH_DIR/value-objects.json")
RELATIONSHIP_COUNT=$(jq '. | length' "$GRAPH_DIR/relationships.json")

row "Actors (people & teams)" "${GREEN}$ACTOR_COUNT${NC}"
row "Workflows" "${GREEN}$WORKFLOW_COUNT${NC}"
row "Decisions" "${GREEN}$DECISION_COUNT${NC}"
row "Commitments" "${GREEN}$COMMITMENT_COUNT${NC}"
row "Value Objects" "${GREEN}$VALUE_OBJECT_COUNT${NC}"
row "Relationships (edges)" "${GREEN}$RELATIONSHIP_COUNT${NC}"

TOTAL=$((ACTOR_COUNT + WORKFLOW_COUNT + DECISION_COUNT + COMMITMENT_COUNT + VALUE_OBJECT_COUNT))
row "Total entities" "${BOLD}${GREEN}$TOTAL${NC}"

# ─────────────────────────────────────────────
# Commitment Status Breakdown
# ─────────────────────────────────────────────
header "Commitment Status Breakdown"

COM_OPEN=$(jq '[.[] | select(.status == "open")] | length' "$GRAPH_DIR/commitments.json")
COM_FULFILLED=$(jq '[.[] | select(.status == "fulfilled")] | length' "$GRAPH_DIR/commitments.json")
COM_BROKEN=$(jq '[.[] | select(.status == "broken")] | length' "$GRAPH_DIR/commitments.json")
COM_OVERDUE=$(jq '[.[] | select(.status == "overdue")] | length' "$GRAPH_DIR/commitments.json")
COM_AT_RISK=$(jq '[.[] | select(.status == "at_risk")] | length' "$GRAPH_DIR/commitments.json")

row "Open" "${CYAN}$COM_OPEN${NC}"
row "Fulfilled" "${GREEN}$COM_FULFILLED${NC}"
row "At Risk" "${YELLOW}$COM_AT_RISK${NC}"
row "Overdue" "${RED}$COM_OVERDUE${NC}"
row "Broken" "${RED}$COM_BROKEN${NC}"

# ─────────────────────────────────────────────
# Open & Overdue Commitments with Due Dates
# ─────────────────────────────────────────────
header "Open & Overdue Commitments"

echo ""
jq -r '.[] | select(.status == "overdue" or .status == "open" or .status == "at_risk") |
  "\(.status | ascii_upcase)\t\(.id)\t\(.due_date)\t\(.priority | ascii_upcase)\t\(.description[:65])..."
' "$GRAPH_DIR/commitments.json" | sort -t$'\t' -k1,1 -k3,3 | while IFS=$'\t' read -r status cid due priority desc; do
  case "$status" in
    "OVERDUE") color="${RED}" ;;
    "AT_RISK")  color="${YELLOW}" ;;
    *)          color="${CYAN}" ;;
  esac
  printf "  ${color}%-10s${NC}  %-8s  %-12s  %-8s  %s\n" "$status" "$cid" "$due" "$priority" "$desc"
done

# ─────────────────────────────────────────────
# Top AI-Candidate Workflows by Score
# ─────────────────────────────────────────────
header "Top AI-Candidate Workflows (by Readiness Score)"

echo ""
printf "  %-6s  %-10s  %-50s  %s\n" "Score" "ID" "Name" "Candidate?"
printf "  %-6s  %-10s  %-50s  %s\n" "──────" "──────────" "──────────────────────────────────────────────────" "──────────"

jq -r '.[] | [.ai_readiness_score, .id, .name, (.ai_candidate | if . then "YES" else "no" end)] | @tsv' \
  "$GRAPH_DIR/workflows.json" | sort -rn | head -10 | \
while IFS=$'\t' read -r score wid name candidate; do
  if [ "$candidate" = "YES" ]; then
    color="${GREEN}"
  else
    color="${YELLOW}"
  fi
  printf "  ${color}%-6s${NC}  %-10s  %-50s  %s\n" "$score" "$wid" "${name:0:50}" "$candidate"
done

# ─────────────────────────────────────────────
# Actors by Job Family
# ─────────────────────────────────────────────
header "Actors by Job Family"

echo ""
jq -r '.[].job_family' "$GRAPH_DIR/actors.json" | sort | uniq -c | sort -rn | \
while read -r count family; do
  row "$family" "$count"
done

# ─────────────────────────────────────────────
# Value Object Health Summary
# ─────────────────────────────────────────────
header "Value Object Health"

echo ""
printf "  %-20s  %-35s  %s\n" "Status" "Name" "Owner"
printf "  %-20s  %-35s  %s\n" "────────────────────" "───────────────────────────────────" "─────────"

jq -r '.[] | [.health_status, .name, .owner] | @tsv' "$GRAPH_DIR/value-objects.json" | \
sort -t$'\t' -k1,1 | \
while IFS=$'\t' read -r health name owner; do
  case "$health" in
    "healthy"|"stable"|"expanding") color="${GREEN}" ;;
    "at_risk"|"degraded") color="${YELLOW}" ;;
    "critical") color="${RED}" ;;
    *) color="${NC}" ;;
  esac
  printf "  ${color}%-20s${NC}  %-35s  %s\n" "$health" "${name:0:35}" "$owner"
done

# ─────────────────────────────────────────────
# Decisions: Valid vs. Stale
# ─────────────────────────────────────────────
header "Decision Currency"

DEC_VALID=$(jq '[.[] | select(.still_valid == true)] | length' "$GRAPH_DIR/decisions.json")
DEC_STALE=$(jq '[.[] | select(.still_valid == false)] | length' "$GRAPH_DIR/decisions.json")

row "Still valid" "${GREEN}$DEC_VALID${NC}"
row "Stale / should be revisited" "${YELLOW}$DEC_STALE${NC}"

echo ""
if [ "$DEC_STALE" -gt 0 ]; then
  echo -e "  ${YELLOW}Stale decisions:${NC}"
  jq -r '.[] | select(.still_valid == false) | "    • \(.id): \(.title)"' "$GRAPH_DIR/decisions.json"
fi

# ─────────────────────────────────────────────
# Footer
# ─────────────────────────────────────────────
echo ""
echo -e "${BLUE}$(printf '═%.0s' {1..52})${NC}"
echo -e "  Run ${CYAN}./scripts/query.sh \"your question\"${NC} to query the graph."
echo -e "  Run ${CYAN}./scripts/validate.sh${NC} to check data integrity."
echo ""
