# Sentra Integration Guide

## Connecting the Veridian Company Graph to Sentra's Live Data Layer

This guide covers how to connect Sentra as the observational data source for the Veridian Company Graph. After setup, Sentra will automatically surface new decisions and commitments from your team's communication tools, which the sync pipeline (`sentra/sync.sh`) can merge into the graph.

**Sentra product used in this guide:** Team plan ($16/seat/month as of 2026)
**Connectors covered:** Slack (required), Google Workspace (recommended), Linear (recommended)
**Estimated time from sign-up to first useful data:** ~2 weeks (Sentra needs time to learn organizational patterns)
**Prerequisites:** Admin access to Slack workspace, Google Workspace admin or delegated access

---

## Overview

The integration has five phases:

```
Phase 1: Sentra account setup
Phase 2: Connect connectors (Slack, Google Workspace, Linear)
Phase 3: Configure entity extraction settings
Phase 4: Test with mock data, then run first live sync
Phase 5: Automate with LaunchAgent or cron
```

After Phase 4, new decisions and commitments that Sentra detects are merged into `graph/decisions.json` and `graph/commitments.json` on each sync run. Human review is required before auto-imported entities go into production use.

---

## Phase 1: Sentra Account Setup

### 1.1 Create a Workspace

1. Go to [sentra.app](https://sentra.app) and sign up. If you want a walkthrough of the initial configuration, book a demo from the homepage — the Sentra team configures the workspace entity extraction settings during onboarding.
2. Create a workspace named **Veridian** (or your company name for real deployments).
3. Set your organization size to **100–250 employees** — this affects extraction sensitivity defaults.
4. Invite the following as workspace Owners: `sarah.chen@veridian.com` (CEO), `fatima.al-rashid@veridian.com` (COO). Owners see the full graph including confidence scores and review queues.

### 1.2 Generate an API Key

1. Navigate to **Settings > API > Create API Key**.
2. Name the key `company-graph-sync`.
3. Permissions needed: `entities:read`, `entities:write`.
4. Copy the key and store it in your team's password manager (1Password, Bitwarden, etc.).
5. Set environment variables for local use:

```bash
export SENTRA_API_KEY="sk-sentra-..."
export SENTRA_WORKSPACE_ID="veridian-workspace-001"
```

Add these to `~/.zshrc` or `~/.bashrc` for persistence, or use a `.env` file in the repo root (ensure `.env` is in `.gitignore`).

### 1.3 Set Organizational Context

In **Settings > Workspace**:
- **Industry:** B2B SaaS / Financial Software
- **Primary language:** English
- **Timezone:** Europe/London
- **Fiscal year start:** January

This helps Sentra calibrate extraction models to your domain. Finance-specific terminology (reconciliation, NRR, ARR, churn, CSM) will be recognized more reliably after workspace context is set.

---

## Phase 2: Connect Connectors

Connect in order of priority. Slack provides the most signal and should go first.

### 2.1 Slack (Required)

Slack is Sentra's primary source for informal commitments, in-progress decisions, and communication patterns.

1. In Sentra: **Connectors > Add Connector > Slack**.
2. Click **Authorize** — this opens the Slack OAuth flow. You need to be a Slack Workspace Admin or have an Admin authorize it.
3. Required Slack scopes: `channels:read`, `channels:history`, `users:read`, `conversations:history`.
4. In the connector settings:
   - **Channel scope:** Include all public channels. Exclude: `#random`, `#social`, `#watercooler`, `#job-board`.
   - **Commitment detection sensitivity:** Set to **Medium**. High generates too many false positives from conversational language ("I'll look into that") — you'll spend more time dismissing bad extractions than reviewing good ones.
   - **Decision extraction keywords:** `we've decided`, `going with`, `agreed to`, `the plan is`, `moving forward with`, `confirmed:`.

5. Wait 24–48 hours. Sentra will backfill up to 90 days of channel history on the first run.

**What to expect:** After the first week, Sentra surfaces 10–30 potential commitments per week. Roughly 25–35% will be genuine commitments worth tracking. The rest are conversational ("can you check that?", "I'll try to make it") and should be dismissed. Assign Fatima Al-Rashid or her EA as the weekly reviewer.

**Veridian-specific channels to prioritize:**
- `#leadership` — decisions and cross-functional commitments
- `#cs-leadership` — customer commitments surface here
- `#engineering-leadership` — internal engineering commitments
- `#product` — commitment language around roadmap and delivery dates
- `#sales` — customer commitment risk; AEs make promises here

### 2.2 Google Workspace (Recommended)

Google Workspace provides meeting context (if transcription is enabled), org chart data, and document-based decisions.

1. In Sentra: **Connectors > Add Connector > Google Workspace**.
2. Authorize with a Google Workspace Admin account. Required OAuth scopes:
   - `admin.directory.user.readonly` — for org chart and actor data
   - `drive.readonly` — document scanning (scope to shared drives only, not personal My Drive)
   - `calendar.readonly` — meeting metadata (titles, attendees, frequency)
3. Configure document scope:
   - **Include shared drives:** Strategy, Customer Success, Engineering Docs, Finance
   - **Exclude:** Personal My Drive folders, Archive drives
4. **Meeting transcript scanning:** This requires Google Meet with transcription enabled (Workspace Business Plus or Enterprise tier). If enabled, Sentra can extract decisions from meeting transcripts — the highest-quality extraction source. If Zoom is used instead, there is no native Zoom connector on the Team plan; consider upgrading or exporting Zoom transcripts manually.

**Note on transcription:** Many teams don't enable transcription by default due to privacy concerns. If you enable it, communicate clearly to the team what data Sentra is collecting and how it will be used.

### 2.3 Linear (Recommended for Engineering Commitments)

Linear provides engineering commitments (delivery dates in ticket descriptions), decision trails from ticket discussions, and workflow activity evidence.

1. In Sentra: **Connectors > Add Connector > Linear**.
2. Generate a Linear API key (read-only) from **Linear > Settings > API > Personal API Keys**. Use a service account if available.
3. In Sentra, enter the API key and authorize the `veridian` workspace.
4. Configure extraction:
   - **Commitments:** Extract from ticket `due_date` fields, descriptions containing "will be done by", "target:", "committed to"
   - **Decisions:** Extract from ticket comments with explicit decision language

**Important manual tag:** After connecting, manually tag the following Linear projects in Sentra to link them to existing graph decisions:
- `FWE Test Coverage` → `dec-008` (tech debt freeze)
- `Admin SSO Self-Serve` → `dec-008` and `com-001` (Hartfield SSO commitment)

These cross-references are too important to leave to automated inference.

### Connectors NOT Included in Team Plan

The following connectors require Sentra's Business plan or above:
- **Salesforce** — critical for customer commitment extraction; plan upgrade required
- **GitHub** — useful for engineering commitment tracking
- **Outlook / Microsoft 365** — if your team uses Microsoft instead of Google

For customer commitments specifically, until the Salesforce connector is available, manually seed high-priority commitments from Salesforce opportunity notes into `graph/commitments.json`.

---

## Phase 3: Configure Entity Extraction Settings

After connectors are running for 3–5 days and Sentra has indexed initial data:

### 3.1 Tune Commitment Detection

In **Settings > Entity Extraction > Commitments**:

**Add to the extraction vocabulary:**
- `by end of Q`, `by next quarter`, `before renewal`, `before the board`, `before Hartfield`
- Finance-specific terms: `reconciliation`, `close`, `board pack`, `ARR model`
- Customer names: `Hartfield`, `Meridian`, `Solaris`

**Add to the false-positive blocklist** (these phrases generate too many low-quality extractions):
- `can you`, `would you mind`, `whenever you get a chance`, `might be able to`, `let's see if`

### 3.2 Tune Decision Detection

In **Settings > Entity Extraction > Decisions**:

Add decision-language patterns specific to Veridian's culture:
- `locking in`, `we're going with`, `final call`, `agreed offline`, `Sarah's call`, `Marcus's call`

### 3.3 Set Actor-to-Graph Mappings

Map Sentra's actor identities to Veridian's graph actor IDs. This allows the sync script to replace name strings with `actor-NNN` IDs automatically.

In Sentra: **Actors > [each actor] > Graph ID**, enter:
- Sarah Chen → `actor-001`
- Marcus Webb → `actor-002`
- Priya Sharma → `actor-003`
- (continue for all 20 actors)

Once mapped, auto-extracted entities will use actor IDs in `made_by` and `made_to` fields.

---

## Phase 4: Test with Mock Data, Then Run First Live Sync

### 4.1 Test the Pipeline with Mock Data

Before running against the live Sentra API, verify the sync script works correctly with the mock responses:

```bash
cd /path/to/company-graph-demo

# Dry run first — shows what would be written without writing it
./sentra/sync.sh --mock --dry-run

# Then run for real with mock data
./sentra/sync.sh --mock
```

Expected output:
```
[09:00:01] Starting Veridian Company Graph sync
[09:00:01] Mode: MOCK
[09:00:01] Dry-run: false
[09:00:01] Entity types: all
[09:00:01] Fetching entities since: 2026-03-16T09:00:01Z

[09:00:01] Fetching decisions...
[09:00:01]   Received 3 decision(s) from Sentra
[09:00:01]   3 above threshold (≥0.75) → auto-import queue
[09:00:01]   0 in review zone (0.50–0.74) → human review queue
[09:00:01]   0 below threshold (<0.50) → ignored
  Appended 3 new decisions to /path/to/graph/decisions.json

[09:00:01] Fetching commitments...
[09:00:01]   Received 3 commitment(s) from Sentra
  Appended 3 new commitments to /path/to/graph/commitments.json

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Sync complete: 3 new decisions, 0 updated decisions, 3 new commitments, 0 updated commitments, 0 interactions observed (not imported)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ACTION REQUIRED:
  3 new decision(s) and 3 new commitment(s) were appended.
  Each has id: '__ASSIGN_ID__' — replace with the next sequential ID before using.
```

After the mock run, inspect the auto-imported entities in `graph/decisions.json`. They will have IDs set to `"__ASSIGN_ID__"` and fields marked `"__NEEDS_HUMAN_INPUT__"`. This is expected — they need manual completion before being usable.

Validate the graph:
```bash
./scripts/validate.sh
```

Note: validate.sh will warn about `__ASSIGN_ID__` format — this is expected until IDs are assigned.

Once you've verified the mock run works, revert the mock-added entities (or keep them in a test branch) before running the live sync:

```bash
git diff graph/decisions.json   # review what was added
git checkout graph/decisions.json  # revert if using live data next
git checkout graph/commitments.json
```

### 4.2 Run the First Live Sync

Ensure Sentra has been running for at least 7 days before the first live sync to give it enough data to produce useful extractions.

```bash
export SENTRA_API_KEY="sk-sentra-..."
export SENTRA_WORKSPACE_ID="veridian-workspace-001"

# Dry run first
./sentra/sync.sh --dry-run

# Live sync
./sentra/sync.sh
```

After the first live sync, check `sentra/.sync-state/last-sync.json` for the sync summary.

### 4.3 Review and Promote Auto-Imported Entities

For each auto-imported entity (those with `"_review_status": "pending_human_review"`):

1. Assign a sequential ID (check the last existing ID in the file and increment)
2. Complete all `"__NEEDS_HUMAN_INPUT__"` fields
3. Replace participant name strings with `actor-NNN` IDs
4. Remove the `_sentra_*` metadata fields (or keep them — they don't affect the graph query)
5. Run `./scripts/validate.sh`

Assign this review task to Fatima Al-Rashid (commitments) and the relevant function head (decisions).

---

## Phase 5: Automate with LaunchAgent or Cron

### 5.1 macOS LaunchAgent (recommended for local use)

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
    <string>/Users/YOURUSER/Projects/company-graph-demo/sentra/sync.sh</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>SENTRA_API_KEY</key>
    <string>sk-sentra-YOUR-KEY-HERE</string>
    <key>SENTRA_WORKSPACE_ID</key>
    <string>veridian-workspace-001</string>
  </dict>
  <key>StartInterval</key>
  <integer>14400</integer>
  <key>StandardOutPath</key>
  <string>/tmp/company-graph-sync.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/company-graph-sync-error.log</string>
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
```

Load it:

```bash
launchctl load ~/Library/LaunchAgents/ai.vibrana.company-graph-sync.plist
launchctl start ai.vibrana.company-graph-sync

# Verify it's running
launchctl list | grep company-graph

# Monitor the log
tail -f /tmp/company-graph-sync.log
```

To unload: `launchctl unload ~/Library/LaunchAgents/ai.vibrana.company-graph-sync.plist`

### 5.2 Linux Cron

Add to crontab (`crontab -e`):

```cron
# Sync Veridian Company Graph from Sentra every 4 hours
0 */4 * * * SENTRA_API_KEY=sk-sentra-... SENTRA_WORKSPACE_ID=veridian-workspace-001 /path/to/company-graph-demo/sentra/sync.sh >> /var/log/company-graph-sync.log 2>&1
```

### 5.3 GitHub Actions (best for team repos)

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

      - name: Install jq
        run: sudo apt-get install -y jq

      - name: Sync from Sentra
        env:
          SENTRA_API_KEY: ${{ secrets.SENTRA_API_KEY }}
          SENTRA_WORKSPACE_ID: ${{ secrets.SENTRA_WORKSPACE_ID }}
        run: bash sentra/sync.sh

      - name: Validate graph
        run: bash scripts/validate.sh

      - name: Commit changes if any
        run: |
          git config user.name "Company Graph Bot"
          git config user.email "graph-bot@veridian.com"
          git add graph/
          git diff --cached --quiet || git commit -m "chore: sync graph from Sentra [skip ci]"
          git push
```

Add `SENTRA_API_KEY` and `SENTRA_WORKSPACE_ID` to GitHub repository secrets.

---

## What to Expect: Timeline from Sign-Up to Stable Data

| Week | What's Happening |
|---|---|
| **Week 1** | Sentra indexes Slack history (up to 90 days backfill). Many false positives as the model calibrates. Don't review extractions yet — let it run. |
| **Week 2** | Extraction quality stabilizes. Configure the commitment detection vocabulary and blocklist (Phase 3.1). Run the first review of surfaced entities. Expect ~30% genuine commitments. |
| **Weeks 3–4** | First live sync. Review and promote the highest-confidence entities. Sentra starts recognizing Veridian-specific patterns (customer names, commitment language). |
| **Month 2** | Weekly sync cadence established. Extraction quality meaningfully better — confidence scores rise as Sentra learns organizational vocabulary. |
| **Month 3** | Steady state. Sentra surfaces 2–5 genuinely new commitments and 1–2 decisions per week. Human review becomes a 15-minute weekly task rather than an hour. |

---

## Ongoing Governance

### Review Cadence

| Entity Type | Who Reviews | Cadence | Where |
|---|---|---|---|
| New auto-extracted commitments | Fatima Al-Rashid (COO) | Weekly, Monday | Sentra review queue + `graph/commitments.json` |
| New auto-extracted decisions | Relevant function head | After significant meetings | Sentra review queue |
| Actor changes (joiners, leavers, role changes) | Anya Volkov (People Ops) | As they happen | Rippling → Sentra → graph |
| Stale `still_valid: false` decisions | CEO/leadership team | Quarterly | `graph/decisions.json` |

### The "Commitment Drift" Protocol

When a new commitment is auto-imported with `_review_status: "pending_human_review"`:
1. Fatima or her delegate reviews within 48 hours
2. If genuine: assign ID, complete missing fields, update `_review_status` to `"approved"`
3. If false positive: delete from the JSON file
4. If needs more context: add a note and set `_review_status: "needs_context"` — flag for the commitment's owner to clarify

This keeps the graph clean and the review burden manageable.

---

## Troubleshooting

**Sentra is surfacing too many false-positive commitments from Slack**
- Set commitment detection sensitivity to **Low** in Connector settings
- Add more phrases to the blocklist (see Phase 3.1)
- Exclude high-volume, low-signal channels like `#general` and `#announcements`

**The sync script exits with "SENTRA_API_KEY is not set"**
- Run: `export SENTRA_API_KEY="sk-sentra-..."` and `export SENTRA_WORKSPACE_ID="..."`
- Or use `--mock` to test without credentials

**Auto-imported entities have `__ASSIGN_ID__` and `__NEEDS_HUMAN_INPUT__` fields**
- This is expected — these are the mandatory human review steps
- Replace `__ASSIGN_ID__` with the next sequential ID (`dec-013`, `com-015`, etc.)
- Fill in `__NEEDS_HUMAN_INPUT__` fields with real data from context
- Run `./scripts/validate.sh` to verify

**`./scripts/validate.sh` fails after a sync**
- Check that new entity IDs follow the `type-NNN` format (no `__ASSIGN_ID__` remaining)
- Check that `made_by` and `made_to` fields reference valid `actor-NNN` IDs or valid strings
- Check that `related_workflow` references a valid `wf-NNN` ID

**Sentra is missing customer commitments from sales calls**
- These commitments live in Salesforce, not Slack — the Team plan Salesforce connector is not available
- Manually seed high-priority customer commitments from Salesforce opportunity notes
- For the Hartfield SSO commitment specifically, see `com-001` in `graph/commitments.json`

---

## Support

- Sentra documentation: [docs.sentra.app](https://docs.sentra.app)
- Sentra onboarding: Book a session at sentra.app when signing up (included with Team plan)
- Graph schema questions: See `schema/entities.json` and `schema/relationships.json`
- Vibrana integration support: Contact your Vibrana engagement lead
