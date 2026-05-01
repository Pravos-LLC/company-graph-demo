# Sentra Integration Guide

## Replacing Manual JSON Files with a Live Data Source

This guide covers the steps to connect Sentra as the live data layer for the Veridian Company Graph, transitioning from manually maintained JSON files to a continuously updated organizational memory system.

**Estimated time to complete Phases 1–3:** 2–3 days (with IT access)
**Prerequisites:** Sentra account (Enterprise tier), admin access to Google Workspace, Slack, Linear, Salesforce

---

## Overview

The integration has four phases:

```
Phase 1: Sentra Account Setup + Initial Configuration
Phase 2: Connector Configuration (Slack, Google Workspace, Linear, Salesforce)
Phase 3: Entity Schema Configuration + Initial Seeding
Phase 4: API Export Pipeline + Local Auto-Sync
```

After Phase 4, the JSON files in `graph/` become read replicas — Sentra is the source of truth, and the files are regenerated on a schedule.

---

## Phase 1: Sentra Account Setup

### 1.1 Create a Sentra Organization

1. Go to [sentra.ai](https://sentra.ai) and sign up for an Enterprise account.
2. Name the organization **Veridian** — this becomes the namespace for all entities.
3. Create an Admin user with your corporate email.
4. Invite `sarah.chen@veridian.com` (CEO) and `fatima.al-rashid@veridian.com` (COO) as Owners — they need visibility into the full graph.

### 1.2 Generate an API Key

1. Navigate to **Settings > API > Create API Key**.
2. Name it `company-graph-sync`.
3. Scope it to `entities:read`, `entities:write`, `connectors:read`.
4. Store the key securely: add it to your password manager and to Veridian's 1Password vault under `Engineering > Sentra API Key`.
5. Set it as an environment variable for local development:
   ```bash
   export SENTRA_API_KEY="sk-sentra-..."
   ```

### 1.3 Configure Organizational Metadata

In Sentra's **Organization Settings**:
- **Industry:** Financial Services Software (SaaS)
- **Size:** 51–100 employees
- **Primary language:** English
- **Timezone:** Europe/London
- **Fiscal year start:** January

---

## Phase 2: Connector Configuration

Connectors are the integrations that allow Sentra to observe organizational activity. Configure them in order of priority.

### 2.1 Slack Connector

Slack provides the highest signal for informal commitments, decisions-in-progress, and communication patterns.

1. In Sentra: **Connectors > Add Connector > Slack**.
2. Authorize with a Slack Admin account (requires `channels:read`, `channels:history`, `users:read`).
3. Configure channel scope:
   - **Include:** All public channels, DMs involving leadership team (opt-in required per user)
   - **Exclude:** `#random`, `#social`, `#off-topic`
4. Set the **commitment detection sensitivity** to Medium — high sensitivity generates too many false positives.
5. Enable **decision extraction** from Slack threads that contain phrases like "we've decided", "going with", "agreed to".

**Expected outcomes after 7 days:**
- Sentra will surface 15–40 informal commitments per week from Slack
- ~30% will be genuine commitments worth tracking; the rest are conversational and should be dismissed
- Assign a human reviewer (recommend Fatima Al-Rashid's EA or ops coordinator) to triage weekly

### 2.2 Google Workspace Connector

Google Workspace provides meeting transcripts (if enabled), document decisions, and org chart data.

1. In Sentra: **Connectors > Add Connector > Google Workspace**.
2. Authorize with a Google Workspace Admin account. Required scopes:
   - `admin.directory.user.readonly` (for org chart)
   - `drive.readonly` (for document scanning — limit to specific shared drives)
   - `calendar.readonly` (for meeting metadata)
3. Configure document scope:
   - **Include:** Shared drives: `Strategy`, `Customer Success`, `Product`, `Engineering Docs`
   - **Exclude:** Personal My Drive folders
4. Enable **meeting transcript scanning** if Veridian uses Google Meet with transcription enabled.
5. Set the **document scan depth** to include documents modified in the last 24 months (older documents may generate noise).

**Meeting transcription note:** Google Meet transcripts require the Workspace Business Plus or Enterprise tier and must have transcription enabled per meeting. If Zoom is used instead, configure the Zoom connector following the same steps.

### 2.3 Linear Connector

Linear provides decision trails from ticket activity, project creation, and sprint planning.

1. In Sentra: **Connectors > Add Connector > Linear**.
2. Generate a Linear API key (read-only) from **Linear > Settings > API > Personal API Keys**.
3. In Sentra, enter the API key and authorize the `veridian` workspace.
4. Configure entity extraction:
   - **Decisions:** Extract from ticket comments containing "decision:", "decided:", "rationale:"
   - **Commitments:** Extract from ticket descriptions containing delivery dates and assignees
   - **Value Objects:** Extract project names and labels as potential value objects
5. Enable **workflow correlation**: Sentra will attempt to link Linear project activity to Workflow entities.

**Note on the tech debt freeze:** Linear projects created in January 2026 (`FWE Test Coverage`, `Admin SSO Self-Serve`) should be manually tagged in Sentra as related to `dec-008` (tech debt freeze decision). This cross-reference is too important to leave to automated inference.

### 2.4 Salesforce Connector

Salesforce provides the ground truth for customer commitments — the most critical and most fragile class of commitment for Veridian.

1. In Sentra: **Connectors > Add Connector > Salesforce**.
2. Authorize with a Salesforce Admin account. Sentra requires a Connected App with:
   - `api` scope
   - `refresh_token` scope
   - Read access to: Opportunity, Account, Contact, Task, Note objects
3. Configure commitment extraction:
   - Scan **Opportunity Notes** for commitment language
   - Scan **Tasks** with subject containing "committed", "promised", "deliverable"
   - Scan **Custom Fields** — check if Ravi Patel's team uses any custom commitment tracking fields
4. Map Salesforce Accounts to Veridian ValueObject entities:
   - Hartfield Group → `vo-002`
   - Meridian Capital → `vo-003`
   - Solaris Financial → `vo-004`
5. Set Salesforce as **authoritative** for customer commitment status — Sentra should not override Salesforce data with Slack inferences for customer-type commitments.

**Critical note:** The Hartfield SSO commitment (com-001) is documented in Salesforce opportunity `opp-HG-2024-RNW`. After configuring the connector, manually verify that Sentra has detected and linked this commitment. If not, create it manually using the Sentra UI and link it to the Hartfield account.

---

## Phase 3: Entity Schema Configuration + Initial Seeding

### 3.1 Import the Veridian Schema

Sentra supports custom entity schemas via its configuration API. Import the Veridian schema:

```bash
# Install the Sentra CLI
npm install -g @sentra/cli

# Authenticate
sentra auth login --api-key $SENTRA_API_KEY

# Import entity schemas
sentra schema import --file schema/entities.json --org veridian

# Import relationship rules
sentra schema import --file schema/relationships.json --org veridian --type relationships
```

If the Sentra CLI doesn't support direct JSON Schema import, use the API:

```bash
curl -X POST "https://api.sentra.ai/v1/orgs/veridian/schema" \
  -H "Authorization: Bearer $SENTRA_API_KEY" \
  -H "Content-Type: application/json" \
  -d @schema/entities.json
```

### 3.2 Seed Initial Entities

Import the manually curated graph data as the starting state:

```bash
# Import all entity types
for entity_file in graph/actors.json graph/workflows.json graph/decisions.json \
  graph/commitments.json graph/value-objects.json; do
  entity_type=$(basename "$entity_file" .json)
  echo "Importing $entity_type..."
  sentra entities import \
    --file "$entity_file" \
    --type "$entity_type" \
    --org veridian \
    --conflict-strategy merge
done

# Import relationships
sentra relationships import \
  --file graph/relationships.json \
  --org veridian
```

### 3.3 Set Entity Provenance

For each manually seeded entity, set the `source` field to `manual` so the sync pipeline knows not to overwrite human-curated data:

```bash
sentra entities update-all \
  --org veridian \
  --filter 'source == null' \
  --set 'source=manual,confidence=1.0'
```

Sentra auto-extracted entities will have `source=extracted` and a confidence score <1.0.

### 3.4 Map Connectors to Entities

After seeding, link connector data sources to entity types:
- Slack → Commitments (informal), Decisions (informal)
- Google Workspace → Decisions, Actors (org chart)
- Linear → Workflows, Commitments (delivery dates)
- Salesforce → Commitments (customer), ValueObjects (accounts)

In the Sentra UI: **Entity Settings > Data Sources > Map Sources to Entity Types**.

---

## Phase 4: API Export Pipeline + Local Auto-Sync

### 4.1 Sentra Export API Overview

Sentra's export API returns entities in a format that can be transformed to the Veridian graph schema. The base endpoint:

```
GET https://api.sentra.ai/v1/orgs/veridian/entities?type={type}&format=json
```

### 4.2 Create the Sync Script

Create `scripts/sync-from-sentra.sh`:

```bash
#!/usr/bin/env bash
# sync-from-sentra.sh — Pull latest entity data from Sentra and update graph/
# Run manually or via LaunchAgent (see Phase 4.4)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRAPH_DIR="$REPO_ROOT/graph"
API_BASE="https://api.sentra.ai/v1/orgs/veridian"
SENTRA_API_KEY="${SENTRA_API_KEY:?Error: SENTRA_API_KEY not set}"

echo "Syncing from Sentra at $(date)..."

# Pull each entity type
for entity_type in actors workflows decisions commitments value-objects relationships; do
  output_file="$GRAPH_DIR/${entity_type}.json"
  
  response=$(curl -sf \
    -H "Authorization: Bearer $SENTRA_API_KEY" \
    "$API_BASE/entities?type=$entity_type&format=veridian-schema" 2>/dev/null)
  
  if [ $? -eq 0 ] && [ -n "$response" ]; then
    # Validate that it's valid JSON before overwriting
    if echo "$response" | jq empty 2>/dev/null; then
      echo "$response" > "$output_file"
      echo "  Updated graph/$entity_type.json"
    else
      echo "  WARNING: Invalid JSON from Sentra for $entity_type — skipping"
    fi
  else
    echo "  WARNING: Could not fetch $entity_type from Sentra — skipping"
  fi
done

echo "Running validation..."
bash "$REPO_ROOT/scripts/validate.sh"

echo "Sync complete at $(date)"
```

**Note:** The `?format=veridian-schema` query parameter assumes Sentra supports custom export schemas mapped to the Veridian entity structure (configured in Phase 3.1). If not, you'll need a transformation layer — see Section 4.3.

### 4.3 Transformation Layer (if needed)

If Sentra's native export format doesn't match the Veridian schema, add a `jq` transformation step. Example for Actors:

```bash
# Transform Sentra Actor format to Veridian Actor format
curl -sf "$API_BASE/entities?type=actors" \
  -H "Authorization: Bearer $SENTRA_API_KEY" | \
jq '[.entities[] | {
  id: ("actor-" + (.id | tostring | ltrimstr("0") | if length < 3 then ("000" + .) else . end | .[-3:])),
  name: .full_name,
  role: .title,
  job_family: .department,
  tools_used: (.connected_tools // []),
  current_workflows: (.workflow_memberships // []),
  reports_to: (.manager_id | if . then ("actor-" + .) else null end),
  joined_date: .start_date
}]' > "$GRAPH_DIR/actors.json"
```

### 4.4 Set Up LaunchAgent for Auto-Sync (macOS)

To run the sync automatically every 4 hours on the machine that owns the graph repo:

Create `~/Library/LaunchAgents/ai.vibrana.company-graph-sync.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>ai.vibrana.company-graph-sync</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/YOURUSER/Projects/company-graph-demo/scripts/sync-from-sentra.sh</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>SENTRA_API_KEY</key>
    <string>sk-sentra-YOUR-KEY-HERE</string>
  </dict>
  <key>StartInterval</key>
  <integer>14400</integer>
  <key>StandardOutPath</key>
  <string>/tmp/company-graph-sync.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/company-graph-sync-error.log</string>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
```

Load the agent:

```bash
launchctl load ~/Library/LaunchAgents/ai.vibrana.company-graph-sync.plist
launchctl start ai.vibrana.company-graph-sync
```

Check that it's running:

```bash
launchctl list | grep company-graph
tail -f /tmp/company-graph-sync.log
```

### 4.5 Alternative: GitHub Actions Scheduled Sync

For teams using GitHub, a more robust option is a scheduled GitHub Actions workflow that pulls from Sentra and commits updated graph files:

Create `.github/workflows/sync-graph.yml`:

```yaml
name: Sync Company Graph from Sentra

on:
  schedule:
    - cron: '0 */4 * * *'   # every 4 hours
  workflow_dispatch:          # allow manual trigger

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Sync from Sentra
        env:
          SENTRA_API_KEY: ${{ secrets.SENTRA_API_KEY }}
        run: bash scripts/sync-from-sentra.sh

      - name: Validate graph
        run: bash scripts/validate.sh

      - name: Commit changes
        run: |
          git config user.name "Company Graph Bot"
          git config user.email "graph-bot@veridian.com"
          git add graph/
          git diff --cached --quiet || git commit -m "chore: sync graph from Sentra [skip ci]"
          git push
```

Add `SENTRA_API_KEY` to the GitHub repository secrets.

---

## Phase 5: Ongoing Governance

### Who Reviews What

| Entity Type | Review Owner | Cadence | Decision |
|---|---|---|---|
| New auto-extracted commitments | Fatima Al-Rashid (COO) | Weekly | Approve, dismiss, or escalate |
| New decisions extracted from transcripts | Relevant function head | After each significant meeting | Approve and add rationale |
| Actor updates (role changes, joiners) | Anya Volkov (People Ops) | As they happen | Approve |
| New value objects surfaced by Sentra | Tom Adeyemi or relevant owner | Monthly | Classify and add business value |
| Stale `still_valid=false` decisions | CEO/leadership team | Quarterly | Update or archive |

### Quality Gates

Before any Sentra-extracted entity is promoted to `status: live` in the graph:
1. A human reviewer must approve it
2. The `confidence` score must be >0.7
3. For commitments: the `evidence_source` must be a specific document, message, or meeting (not just "inferred")
4. For decisions: the `rationale` field must be completed by a human (Sentra's extraction is a starting point, not the final record)

### The "Broken Commitment" Protocol

When Sentra detects that a commitment's due date has passed without evidence of fulfillment:
1. Sentra flags it as `status: potentially_broken`
2. The commitment owner receives a Slack notification (via Sentra's alerting)
3. The owner has 48 hours to update the status or add a note
4. If no action: the status escalates to `status: overdue` and the function head is notified
5. If a commitment is marked `broken`: Fatima Al-Rashid is notified directly

This protocol turns the Company Graph from a retrospective record into an active risk management system.

---

## Troubleshooting

### Sentra is extracting too many false-positive commitments from Slack

- Reduce sensitivity to **Low** in **Connectors > Slack > Extraction Settings**
- Add phrases to the blocklist: "can you", "would you", "might be able to", "I think"
- Consider excluding `#general` and `#announcements` from commitment scanning

### Sentra is missing customer commitments from Salesforce

- Verify the Salesforce connector has read access to the `Note` and `Task` objects
- Check that opportunity notes containing commitments use consistent language
- Manually create high-priority commitments in Sentra and link to the Salesforce opportunity URL

### The sync script fails with schema validation errors

- Run `./scripts/validate.sh` to identify the specific field that's failing
- Check if Sentra has added new fields or changed field names in a schema update
- Review the Sentra changelog and update the transformation layer accordingly

### A decision captured by Sentra is missing its dissenting views

- This is expected — Sentra can extract the decision but not the disagreement unless it was stated explicitly in a transcript
- Add dissenting views manually via `sentra entities update --id dec-NNN --field dissenting_views`
- Consider adding a "decision documentation" ritual at the end of key meetings where the facilitator explicitly asks for dissenting views on the record

---

## Support

- Sentra documentation: [docs.sentra.ai](https://docs.sentra.ai)
- Vibrana integration support: Contact your Vibrana engagement lead
- Graph schema questions: See `schema/entities.json` and `schema/relationships.json`
