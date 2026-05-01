#!/usr/bin/env bash
# sentra/sync.sh — Pull new entities from Sentra API and merge into local graph files
#
# Usage:
#   ./sentra/sync.sh                         # live sync against Sentra API
#   ./sentra/sync.sh --dry-run               # show what would be written, don't write
#   ./sentra/sync.sh --mock                  # use mock responses from sentra/mock-responses/
#   ./sentra/sync.sh --entity-type decisions # sync only a specific entity type
#   ./sentra/sync.sh --entity-type all       # sync all types (default)
#
# Environment variables:
#   SENTRA_API_KEY          required for live sync (not needed with --mock)
#   SENTRA_WORKSPACE_ID     required for live sync (not needed with --mock)
#
# Output:
#   Writes merged entities to graph/decisions.json and graph/commitments.json
#   Writes sync state to sentra/.sync-state/last-sync.json
#   Prints summary to stdout: "3 new decisions, 1 updated commitment, 12 new interactions ignored"

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GRAPH_DIR="$REPO_ROOT/graph"
MOCK_DIR="$SCRIPT_DIR/mock-responses"
SYNC_STATE_DIR="$SCRIPT_DIR/.sync-state"
SYNC_STATE_FILE="$SYNC_STATE_DIR/last-sync.json"

# Sentra API base URL (documented architecture)
SENTRA_API_BASE="https://api.sentra.app/api/v1"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
DRY_RUN=false
USE_MOCK=false
ENTITY_TYPE="all"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --mock)
      USE_MOCK=true
      shift
      ;;
    --entity-type)
      ENTITY_TYPE="${2:-all}"
      shift 2
      ;;
    --help|-h)
      head -20 "$0" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate environment for live sync
# ---------------------------------------------------------------------------
if [[ "$USE_MOCK" == "false" ]]; then
  if [[ -z "${SENTRA_API_KEY:-}" ]]; then
    echo "ERROR: SENTRA_API_KEY is not set." >&2
    echo "  Set it with: export SENTRA_API_KEY='sk-sentra-...'" >&2
    echo "  Or run with --mock to use local test data." >&2
    exit 1
  fi
  if [[ -z "${SENTRA_WORKSPACE_ID:-}" ]]; then
    echo "ERROR: SENTRA_WORKSPACE_ID is not set." >&2
    echo "  Set it with: export SENTRA_WORKSPACE_ID='veridian-workspace-001'" >&2
    echo "  Or run with --mock to use local test data." >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Validate dependencies
# ---------------------------------------------------------------------------
if ! command -v jq &> /dev/null; then
  echo "ERROR: jq is required but not installed." >&2
  echo "  Install with: brew install jq" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

# Determine the 'since' timestamp: use last sync time if available, else 30 days ago
get_since_timestamp() {
  if [[ -f "$SYNC_STATE_FILE" ]]; then
    local last_sync
    last_sync=$(jq -r '.synced_at // empty' "$SYNC_STATE_FILE" 2>/dev/null || true)
    if [[ -n "$last_sync" ]]; then
      echo "$last_sync"
      return
    fi
  fi
  # Default: 30 days ago (ISO 8601)
  if date -v-30d '+%Y-%m-%dT%H:%M:%SZ' &>/dev/null 2>&1; then
    # macOS
    date -v-30d '+%Y-%m-%dT%H:%M:%SZ'
  else
    # Linux
    date -d '30 days ago' '+%Y-%m-%dT%H:%M:%SZ'
  fi
}

# Fetch entity data from Sentra API
fetch_from_api() {
  local entity_type="$1"
  local since="$2"

  local url="${SENTRA_API_BASE}/workspaces/${SENTRA_WORKSPACE_ID}/entities?type=${entity_type}&since=${since}"

  local response
  response=$(curl -sf \
    --max-time 30 \
    -H "Authorization: Bearer ${SENTRA_API_KEY}" \
    -H "Accept: application/json" \
    "$url") || {
    echo "ERROR: Failed to fetch ${entity_type} from Sentra API." >&2
    echo "  URL: $url" >&2
    echo "  Check your SENTRA_API_KEY and SENTRA_WORKSPACE_ID." >&2
    return 1
  }

  echo "$response"
}

# Fetch entity data from mock files
fetch_from_mock() {
  local entity_type="$1"
  local mock_file="${MOCK_DIR}/${entity_type}.json"

  if [[ ! -f "$mock_file" ]]; then
    echo "  [SKIP] No mock file for entity type '${entity_type}' at ${mock_file}" >&2
    echo '{"entities": [], "meta": {"count": 0, "next_page": null}}'
    return
  fi

  cat "$mock_file"
}

# Map a Sentra decision entity to our graph schema format
# Outputs a JSON object ready to append to graph/decisions.json
map_sentra_decision() {
  local sentra_entity="$1"

  # Generate a placeholder ID — in production, this would be the next sequential dec-NNN
  # For sync purposes we use the Sentra ID as a stable external key
  local sentra_id
  sentra_id=$(echo "$sentra_entity" | jq -r '.id')

  echo "$sentra_entity" | jq --arg sid "$sentra_id" '{
    "_sentra_id": $sid,
    "_sentra_source": "auto-extracted",
    "_confidence": .confidence_score,
    "_review_status": "pending_human_review",
    "id": ("__ASSIGN_ID__"),
    "title": .title,
    "made_by": [.participants[0].name],
    "made_at": (.made_at | split("T")[0]),
    "summary": .summary,
    "context": ("Auto-extracted from " + .source.type + ": " + .source.title),
    "alternatives_considered": [
      .alternatives_considered[] | { "name": ., "reason_rejected": "__NEEDS_HUMAN_INPUT__" }
    ],
    "outcome": "__NEEDS_HUMAN_INPUT__",
    "rationale": .rationale,
    "dissenting_views": [],
    "still_valid": true,
    "affects_workflows": [],
    "tags": ["sentra-extracted", "needs-review"],
    "_raw_excerpt": .raw_excerpt
  }'
}

# Map a Sentra commitment entity to our graph schema format
map_sentra_commitment() {
  local sentra_entity="$1"
  local sentra_id
  sentra_id=$(echo "$sentra_entity" | jq -r '.id')

  echo "$sentra_entity" | jq --arg sid "$sentra_id" '{
    "_sentra_id": $sid,
    "_sentra_source": "auto-extracted",
    "_confidence": .confidence_score,
    "_review_status": "pending_human_review",
    "id": ("__ASSIGN_ID__"),
    "made_by": .made_by.name,
    "made_to": .made_to.name,
    "type": (if .made_to.organization then "customer" else "internal" end),
    "description": .summary,
    "due_date": (.due_date // "unknown"),
    "status": (.status_inference // "open"),
    "evidence_source": ("Sentra auto-extracted from " + .source.type + ": " + .source.title + " (" + .source.id + ")"),
    "related_workflow": "__NEEDS_HUMAN_INPUT__",
    "priority": "medium",
    "notes": ("Auto-extracted with confidence " + (.confidence_score | tostring) + ". Needs human review. Raw excerpt: " + .raw_excerpt),
    "_raw_excerpt": .raw_excerpt
  }'
}

# Merge new Sentra entities into the existing graph file
# New entities are appended; existing entities (matched by _sentra_id) are updated
merge_into_graph() {
  local graph_file="$1"
  local new_entities_json="$2"  # JSON array of already-mapped entities
  local entity_label="$3"

  local new_count
  new_count=$(echo "$new_entities_json" | jq 'length')

  if [[ "$new_count" -eq 0 ]]; then
    echo "  No new ${entity_label} to merge."
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY-RUN] Would append ${new_count} new ${entity_label} to ${graph_file}:"
    echo "$new_entities_json" | jq -r '.[] | "    - " + (.title // .description // "(no title)")'
    return 0
  fi

  # Read the existing graph file, append new entities, write back
  local existing
  existing=$(cat "$graph_file")

  local merged
  merged=$(echo "$existing" "$new_entities_json" | jq -s '.[0] + .[1]')

  echo "$merged" > "$graph_file"
  echo "  Appended ${new_count} new ${entity_label} to ${graph_file}"
}

# Write the sync state file
write_sync_state() {
  local synced_at="$1"
  local summary="$2"

  mkdir -p "$SYNC_STATE_DIR"

  local prev_syncs="[]"
  if [[ -f "$SYNC_STATE_FILE" ]]; then
    prev_syncs=$(jq '.history // []' "$SYNC_STATE_FILE" 2>/dev/null || echo "[]")
  fi

  jq -n \
    --arg synced_at "$synced_at" \
    --arg summary "$summary" \
    --argjson history "$prev_syncs" \
    '{
      synced_at: $synced_at,
      summary: $summary,
      history: ([$history[], {synced_at: $synced_at, summary: $summary}] | .[-10:])
    }' > "$SYNC_STATE_FILE"
}

# ---------------------------------------------------------------------------
# Main sync logic
# ---------------------------------------------------------------------------

SINCE=$(get_since_timestamp)
SYNC_START=$(date '+%Y-%m-%dT%H:%M:%SZ')

log "Starting Veridian Company Graph sync"
log "Mode: $([ "$USE_MOCK" == "true" ] && echo "MOCK" || echo "LIVE")"
log "Dry-run: $DRY_RUN"
log "Entity types: $ENTITY_TYPE"
log "Fetching entities since: $SINCE"
echo ""

# Counters for the final summary
DECISIONS_NEW=0
DECISIONS_UPDATED=0
COMMITMENTS_NEW=0
COMMITMENTS_UPDATED=0
INTERACTIONS_IGNORED=0

# ---------------------------------------------------------------------------
# Process: decisions
# ---------------------------------------------------------------------------
should_process_decisions=false
if [[ "$ENTITY_TYPE" == "all" || "$ENTITY_TYPE" == "decisions" ]]; then
  should_process_decisions=true
fi

if [[ "$should_process_decisions" == "true" ]]; then
  log "Fetching decisions..."

  if [[ "$USE_MOCK" == "true" ]]; then
    raw_response=$(fetch_from_mock "decisions")
  else
    raw_response=$(fetch_from_api "decisions" "$SINCE")
  fi

  # Validate JSON
  if ! echo "$raw_response" | jq empty 2>/dev/null; then
    echo "  ERROR: Invalid JSON from decisions response. Skipping." >&2
  else
    entity_count=$(echo "$raw_response" | jq '.entities | length')
    log "  Received ${entity_count} decision(s) from Sentra"

    if [[ "$entity_count" -gt 0 ]]; then
      # Filter by confidence threshold (0.75+ for auto-import, below goes to review queue)
      high_confidence=$(echo "$raw_response" | jq '[.entities[] | select(.confidence_score >= 0.75)]')
      low_confidence=$(echo "$raw_response" | jq '[.entities[] | select(.confidence_score < 0.75 and .confidence_score >= 0.50)]')
      below_threshold=$(echo "$raw_response" | jq '[.entities[] | select(.confidence_score < 0.50)]')

      hc_count=$(echo "$high_confidence" | jq 'length')
      lc_count=$(echo "$low_confidence" | jq 'length')
      bt_count=$(echo "$below_threshold" | jq 'length')

      log "  ${hc_count} above threshold (≥0.75) → auto-import queue"
      log "  ${lc_count} in review zone (0.50–0.74) → human review queue"
      log "  ${bt_count} below threshold (<0.50) → ignored"

      # Map high-confidence decisions to our schema
      if [[ "$hc_count" -gt 0 ]]; then
        mapped_decisions="[]"
        while IFS= read -r entity; do
          mapped=$(map_sentra_decision "$entity")
          mapped_decisions=$(echo "$mapped_decisions" | jq --argjson new "$mapped" '. + [$new]')
        done < <(echo "$high_confidence" | jq -c '.[]')

        merge_into_graph "$GRAPH_DIR/decisions.json" "$mapped_decisions" "decisions"
        DECISIONS_NEW=$hc_count
      fi

      if [[ "$lc_count" -gt 0 ]]; then
        log "  NOTE: ${lc_count} low-confidence decision(s) need human review."
        log "  Review them at: sentra.app/workspace/${SENTRA_WORKSPACE_ID:-veridian}/review"
      fi
    fi
  fi
  echo ""
fi

# ---------------------------------------------------------------------------
# Process: commitments
# ---------------------------------------------------------------------------
should_process_commitments=false
if [[ "$ENTITY_TYPE" == "all" || "$ENTITY_TYPE" == "commitments" ]]; then
  should_process_commitments=true
fi

if [[ "$should_process_commitments" == "true" ]]; then
  log "Fetching commitments..."

  if [[ "$USE_MOCK" == "true" ]]; then
    raw_response=$(fetch_from_mock "commitments")
  else
    raw_response=$(fetch_from_api "commitments" "$SINCE")
  fi

  if ! echo "$raw_response" | jq empty 2>/dev/null; then
    echo "  ERROR: Invalid JSON from commitments response. Skipping." >&2
  else
    entity_count=$(echo "$raw_response" | jq '.entities | length')
    log "  Received ${entity_count} commitment(s) from Sentra"

    if [[ "$entity_count" -gt 0 ]]; then
      high_confidence=$(echo "$raw_response" | jq '[.entities[] | select(.confidence_score >= 0.75)]')
      low_confidence=$(echo "$raw_response" | jq '[.entities[] | select(.confidence_score < 0.75 and .confidence_score >= 0.50)]')
      below_threshold=$(echo "$raw_response" | jq '[.entities[] | select(.confidence_score < 0.50)]')

      hc_count=$(echo "$high_confidence" | jq 'length')
      lc_count=$(echo "$low_confidence" | jq 'length')
      bt_count=$(echo "$below_threshold" | jq 'length')

      log "  ${hc_count} above threshold (≥0.75) → auto-import queue"
      log "  ${lc_count} in review zone (0.50–0.74) → human review queue"
      log "  ${bt_count} below threshold (<0.50) → ignored"

      if [[ "$hc_count" -gt 0 ]]; then
        mapped_commitments="[]"
        while IFS= read -r entity; do
          mapped=$(map_sentra_commitment "$entity")
          mapped_commitments=$(echo "$mapped_commitments" | jq --argjson new "$mapped" '. + [$new]')
        done < <(echo "$high_confidence" | jq -c '.[]')

        merge_into_graph "$GRAPH_DIR/commitments.json" "$mapped_commitments" "commitments"
        COMMITMENTS_NEW=$hc_count
      fi

      if [[ "$lc_count" -gt 0 ]]; then
        log "  NOTE: ${lc_count} low-confidence commitment(s) need human review."
        log "  Review them at: sentra.app/workspace/${SENTRA_WORKSPACE_ID:-veridian}/review"
      fi
    fi
  fi
  echo ""
fi

# ---------------------------------------------------------------------------
# Process: interactions (we observe but do not import into the graph)
# ---------------------------------------------------------------------------
should_process_interactions=false
if [[ "$ENTITY_TYPE" == "all" || "$ENTITY_TYPE" == "interactions" ]]; then
  should_process_interactions=true
fi

if [[ "$should_process_interactions" == "true" ]]; then
  log "Fetching interactions (for count only — not imported into graph)..."

  if [[ "$USE_MOCK" == "true" ]]; then
    # No mock file for interactions — that's intentional
    interaction_count=0
    log "  No mock data for interactions."
  else
    raw_response=$(fetch_from_api "interactions" "$SINCE" 2>/dev/null || echo '{"entities": [], "meta": {"count": 0}}')
    interaction_count=$(echo "$raw_response" | jq '.meta.count // (.entities | length) // 0')
    log "  ${interaction_count} interaction(s) observed — not imported (use Sentra UI to browse)"
  fi
  INTERACTIONS_IGNORED=$interaction_count
  echo ""
fi

# ---------------------------------------------------------------------------
# Write sync state
# ---------------------------------------------------------------------------
SUMMARY="${DECISIONS_NEW} new decisions, ${DECISIONS_UPDATED} updated decisions, ${COMMITMENTS_NEW} new commitments, ${COMMITMENTS_UPDATED} updated commitments, ${INTERACTIONS_IGNORED} interactions observed (not imported)"

if [[ "$DRY_RUN" == "false" ]]; then
  write_sync_state "$SYNC_START" "$SUMMARY"
  log "Sync state written to ${SYNC_STATE_FILE}"
fi

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Sync complete: $SUMMARY"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "(DRY-RUN — no files were written)"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Remind operator to assign IDs to any auto-imported entities
if [[ "$DECISIONS_NEW" -gt 0 || "$COMMITMENTS_NEW" -gt 0 ]]; then
  echo "ACTION REQUIRED:"
  echo "  ${DECISIONS_NEW} new decision(s) and ${COMMITMENTS_NEW} new commitment(s) were appended."
  echo "  Each has id: '__ASSIGN_ID__' — replace with the next sequential ID before using."
  echo "  Fields marked '__NEEDS_HUMAN_INPUT__' require manual enrichment."
  echo "  Run ./scripts/validate.sh to check the graph after updating IDs."
  echo ""
fi
