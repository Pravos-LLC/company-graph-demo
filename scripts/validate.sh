#!/usr/bin/env bash
# validate.sh — Validates all graph JSON files and checks cross-references
# Usage: ./scripts/validate.sh
# Dependencies: jq (brew install jq)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRAPH_DIR="$REPO_ROOT/graph"
SCHEMA_DIR="$REPO_ROOT/schema"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; WARN=$((WARN + 1)); }
section() { echo -e "\n${BLUE}━━ $1${NC}"; }

# ─────────────────────────────────────────────
# 1. JSON Syntax Validation
# ─────────────────────────────────────────────
section "JSON Syntax Validation"

GRAPH_FILES=(
  "actors.json"
  "workflows.json"
  "decisions.json"
  "commitments.json"
  "value-objects.json"
  "relationships.json"
)

SCHEMA_FILES=(
  "entities.json"
  "relationships.json"
)

for file in "${GRAPH_FILES[@]}"; do
  path="$GRAPH_DIR/$file"
  if [ ! -f "$path" ]; then
    fail "Missing file: graph/$file"
  elif jq empty "$path" 2>/dev/null; then
    pass "graph/$file — valid JSON"
  else
    fail "graph/$file — INVALID JSON ($(jq empty "$path" 2>&1 | head -1))"
  fi
done

for file in "${SCHEMA_FILES[@]}"; do
  path="$SCHEMA_DIR/$file"
  if [ ! -f "$path" ]; then
    fail "Missing file: schema/$file"
  elif jq empty "$path" 2>/dev/null; then
    pass "schema/$file — valid JSON"
  else
    fail "schema/$file — INVALID JSON"
  fi
done

# ─────────────────────────────────────────────
# 2. Entity ID Format Validation
# ─────────────────────────────────────────────
section "Entity ID Format Validation"

check_id_format() {
  local file="$1"
  local pattern="$2"
  local entity_name="$3"

  if [ ! -f "$file" ]; then return; fi

  local bad_ids
  bad_ids=$(jq -r '.[].id' "$file" | grep -vE "$pattern" || true)
  if [ -z "$bad_ids" ]; then
    pass "$entity_name — all IDs match pattern $pattern"
  else
    fail "$entity_name — IDs with wrong format: $bad_ids"
  fi
}

check_id_format "$GRAPH_DIR/actors.json"        "^actor-[0-9]{3,}$"  "Actors"
check_id_format "$GRAPH_DIR/workflows.json"     "^wf-[0-9]{3,}$"     "Workflows"
check_id_format "$GRAPH_DIR/decisions.json"     "^dec-[0-9]{3,}$"    "Decisions"
check_id_format "$GRAPH_DIR/commitments.json"   "^com-[0-9]{3,}$"    "Commitments"
check_id_format "$GRAPH_DIR/value-objects.json" "^vo-[0-9]{3,}$"     "ValueObjects"
check_id_format "$GRAPH_DIR/relationships.json" "^rel-[0-9]{3,}$"    "Relationships"

# ─────────────────────────────────────────────
# 3. ID Uniqueness
# ─────────────────────────────────────────────
section "ID Uniqueness Check"

check_unique_ids() {
  local file="$1"
  local label="$2"

  if [ ! -f "$file" ]; then return; fi

  local total dupes
  total=$(jq '.[].id' "$file" | wc -l | tr -d ' ')
  dupes=$(jq -r '.[].id' "$file" | sort | uniq -d)

  if [ -z "$dupes" ]; then
    pass "$label — $total unique IDs"
  else
    fail "$label — duplicate IDs found: $dupes"
  fi
}

check_unique_ids "$GRAPH_DIR/actors.json"        "Actors"
check_unique_ids "$GRAPH_DIR/workflows.json"     "Workflows"
check_unique_ids "$GRAPH_DIR/decisions.json"     "Decisions"
check_unique_ids "$GRAPH_DIR/commitments.json"   "Commitments"
check_unique_ids "$GRAPH_DIR/value-objects.json" "ValueObjects"
check_unique_ids "$GRAPH_DIR/relationships.json" "Relationships"

# ─────────────────────────────────────────────
# 4. Cross-Reference Validation (from_id / to_id)
# ─────────────────────────────────────────────
section "Cross-Reference Validation"

# Build a master set of all valid entity IDs
ALL_IDS=$(
  jq -r '.[].id' "$GRAPH_DIR/actors.json" \
  "$GRAPH_DIR/workflows.json" \
  "$GRAPH_DIR/decisions.json" \
  "$GRAPH_DIR/commitments.json" \
  "$GRAPH_DIR/value-objects.json" \
  "$GRAPH_DIR/relationships.json" 2>/dev/null | sort -u
)

validate_ref() {
  local id="$1"
  echo "$ALL_IDS" | grep -qx "$id"
}

# Check relationship from_id and to_id
BROKEN_REFS=0
while IFS= read -r rel_id; do
  from_id=$(jq -r --arg id "$rel_id" '.[] | select(.id == $id) | .from_id' "$GRAPH_DIR/relationships.json")
  to_id=$(jq -r --arg id "$rel_id" '.[] | select(.id == $id) | .to_id' "$GRAPH_DIR/relationships.json")

  if ! validate_ref "$from_id"; then
    fail "Relationship $rel_id — from_id '$from_id' does not exist"
    ((BROKEN_REFS++))
  fi
  if ! validate_ref "$to_id"; then
    fail "Relationship $rel_id — to_id '$to_id' does not exist"
    ((BROKEN_REFS++))
  fi
done < <(jq -r '.[].id' "$GRAPH_DIR/relationships.json")

if [ "$BROKEN_REFS" -eq 0 ]; then
  pass "Relationships — all from_id and to_id references are valid"
fi

# Check workflow owner references
BAD_OWNERS=0
while IFS= read -r owner_id; do
  if [ -n "$owner_id" ] && ! echo "$ALL_IDS" | grep -qx "$owner_id"; then
    fail "Workflow owner '$owner_id' does not reference a valid actor"
    ((BAD_OWNERS++))
  fi
done < <(jq -r '.[].owner' "$GRAPH_DIR/workflows.json")

if [ "$BAD_OWNERS" -eq 0 ]; then
  pass "Workflow owners — all owner IDs reference valid actors"
fi

# Check commitment made_by references
BAD_MADE_BY=0
while IFS= read -r actor_id; do
  if ! echo "$ALL_IDS" | grep -qx "$actor_id"; then
    fail "Commitment made_by '$actor_id' does not reference a valid actor"
    ((BAD_MADE_BY++))
  fi
done < <(jq -r '.[].made_by' "$GRAPH_DIR/commitments.json")

if [ "$BAD_MADE_BY" -eq 0 ]; then
  pass "Commitment made_by — all references are valid"
fi

# Check commitment related_workflow references
BAD_WF_REFS=0
while IFS= read -r wf_id; do
  if ! echo "$ALL_IDS" | grep -qx "$wf_id"; then
    fail "Commitment related_workflow '$wf_id' does not reference a valid workflow"
    ((BAD_WF_REFS++))
  fi
done < <(jq -r '.[].related_workflow' "$GRAPH_DIR/commitments.json")

if [ "$BAD_WF_REFS" -eq 0 ]; then
  pass "Commitment related_workflow — all references are valid"
fi

# ─────────────────────────────────────────────
# 5. Required Fields Check
# ─────────────────────────────────────────────
section "Required Fields Check"

check_required_field() {
  local file="$1"
  local field="$2"
  local label="$3"

  if [ ! -f "$file" ]; then return; fi

  local missing
  missing=$(jq -r --arg f "$field" '.[] | select(.[$f] == null or .[$f] == "") | .id' "$file" 2>/dev/null || true)

  if [ -z "$missing" ]; then
    pass "$label.$field — present in all records"
  else
    fail "$label.$field — missing in: $missing"
  fi
}

check_required_field "$GRAPH_DIR/actors.json"        "name"              "Actor"
check_required_field "$GRAPH_DIR/actors.json"        "job_family"        "Actor"
check_required_field "$GRAPH_DIR/workflows.json"     "owner"             "Workflow"
check_required_field "$GRAPH_DIR/workflows.json"     "ai_readiness_score" "Workflow"
check_required_field "$GRAPH_DIR/decisions.json"     "rationale"         "Decision"
check_required_field "$GRAPH_DIR/decisions.json"     "still_valid"       "Decision"
check_required_field "$GRAPH_DIR/commitments.json"   "status"            "Commitment"
check_required_field "$GRAPH_DIR/commitments.json"   "due_date"          "Commitment"
check_required_field "$GRAPH_DIR/value-objects.json" "health_status"     "ValueObject"
check_required_field "$GRAPH_DIR/value-objects.json" "owner"             "ValueObject"

# ─────────────────────────────────────────────
# 6. Business Logic Warnings
# ─────────────────────────────────────────────
section "Business Logic Warnings"

# Workflows with no relationships
WORKFLOW_IDS=$(jq -r '.[].id' "$GRAPH_DIR/workflows.json")
while IFS= read -r wf_id; do
  rel_count=$(jq -r --arg id "$wf_id" '[.[] | select(.from_id == $id or .to_id == $id)] | length' "$GRAPH_DIR/relationships.json")
  if [ "$rel_count" -eq 0 ]; then
    warn "Workflow $wf_id has no relationships in relationships.json"
  fi
done <<< "$WORKFLOW_IDS"

# Overdue commitments
OVERDUE=$(jq -r '.[] | select(.status == "overdue") | "  • \(.id): \(.description[:60])..."' "$GRAPH_DIR/commitments.json")
if [ -n "$OVERDUE" ]; then
  warn "Overdue commitments found (review urgently):"
  echo "$OVERDUE"
fi

# Decisions with still_valid = false (stale decisions affecting live workflows)
STALE=$(jq -r '.[] | select(.still_valid == false) | "  • \(.id): \(.title)"' "$GRAPH_DIR/decisions.json")
if [ -n "$STALE" ]; then
  warn "Decisions marked still_valid=false but may still affect workflows:"
  echo "$STALE"
fi

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}PASS: $PASS${NC}  |  ${RED}FAIL: $FAIL${NC}  |  ${YELLOW}WARN: $WARN${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo -e "${RED}Validation failed with $FAIL error(s). Fix before querying or updating the graph.${NC}"
  exit 1
else
  echo ""
  echo -e "${GREEN}All checks passed.${NC}"
  exit 0
fi
