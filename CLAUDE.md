# Company Graph — Claude Code Instructions

This repo is the **Veridian Company Graph**: a structured, agent-queryable knowledge base representing how a fictional company (Veridian) is actually organized — its people, workflows, decisions, commitments, and value objects.

It is used as a demo/proof-of-concept by **Vibrana** (an AI transformation consultancy) to show enterprise clients what a living institutional memory looks like and how AI agents can query it.

---

## What's in This Repo

```
graph/               The actual data — 6 JSON files, one per entity type
schema/              JSON Schema definitions + relationship rules
scripts/             validate.sh, stats.sh, query.sh
sentra/              Integration docs for connecting Sentra as live data source
README.md            Client-facing overview + quickstart
CLAUDE.md            This file — agent instructions
```

### Graph Files (the data)

| File | Contents | Count |
|---|---|---|
| `graph/actors.json` | People and teams: name, role, job family, tools, workflows, reporting line | 12 |
| `graph/workflows.json` | Business processes: steps, tools, pain points, AI readiness scores | 15 |
| `graph/decisions.json` | Key decisions: rationale, alternatives, dissenting views, validity | 9 |
| `graph/commitments.json` | Open/fulfilled/broken promises: customer, internal, vendor | 12 |
| `graph/value-objects.json` | Products, customers, data assets, capital: ownership, health | 9 |
| `graph/relationships.json` | Explicit edges between entities: type, strength, date | 35 |

### Entity ID Conventions

- Actors: `actor-001` through `actor-012`
- Workflows: `wf-001` through `wf-015`
- Decisions: `dec-001` through `dec-009`
- Commitments: `com-001` through `com-012`
- Value Objects: `vo-001` through `vo-009`
- Relationships: `rel-001` through `rel-035`

---

## How to Query the Graph

Use `./scripts/query.sh` to ask natural language questions. The script loads all graph data and calls the Claude API.

```bash
export ANTHROPIC_API_KEY=sk-ant-...

./scripts/query.sh "What are our open customer commitments?"
./scripts/query.sh "Which workflows are most ready for AI automation?"
./scripts/query.sh "Why did we kill the CS triage AI pilot?"
./scripts/query.sh "What decisions affect the Hartfield Group account?"
./scripts/query.sh "Who owns the Finance Workflow Engine?"
./scripts/query.sh "What is blocking delivery of the Hartfield SSO?"
./scripts/query.sh "Show me all broken or overdue commitments"
./scripts/query.sh "What are the top risks to our Series C story?"
./scripts/query.sh "What did Ravi Patel commit to, and are those commitments on track?"
./scripts/query.sh "Which of our decisions are now stale and should be revisited?"
```

The query script uses `claude-sonnet-4-6` with a system prompt that positions it as Veridian's Company Intelligence Assistant. Typical response time: 5–12 seconds.

**Dependencies:** `jq` (install with `brew install jq`), `curl`, `ANTHROPIC_API_KEY`

---

## How to Get Graph Stats

```bash
./scripts/stats.sh
```

Prints: entity counts, commitment status breakdown, top AI-candidate workflows, value object health, actor distribution, and stale decisions. No API key required — runs entirely with `jq`.

---

## How to Validate the Graph

```bash
./scripts/validate.sh
```

Checks:
1. JSON syntax validity for all 8 graph + schema files
2. Entity ID format (actor-NNN, wf-NNN, etc.)
3. ID uniqueness within each entity type
4. Cross-reference integrity (relationship from_id/to_id exist)
5. Required fields presence
6. Business logic warnings (ownerless workflows, overdue commitments, stale decisions)

Run validate after any manual edits. The script exits 0 on pass, 1 on failure.

---

## How to Update Entities

All entities are stored as plain JSON arrays. To update an entity:

1. Open the relevant file in `graph/`
2. Find the entity by its ID
3. Edit the fields directly
4. Run `./scripts/validate.sh` to confirm no cross-references are broken
5. Commit the change with a descriptive message:
   ```
   git add graph/commitments.json
   git commit -m "update: com-001 status to at_risk after Hartfield call"
   ```

### Adding a New Entity

1. Add a new JSON object to the appropriate file
2. Use the next sequential ID (e.g., if the last actor is `actor-012`, use `actor-013`)
3. Follow the schema in `schema/entities.json` for required fields
4. If the entity connects to others, add relationships to `graph/relationships.json`
5. Validate

### Common Updates

**Updating commitment status:**
```json
// In graph/commitments.json, find the commitment and change:
"status": "open"  →  "status": "fulfilled"
// Add a note:
"notes": "SSO delivered and tested by James Okafor on April 28, 2026."
```

**Marking a decision as stale:**
```json
// In graph/decisions.json:
"still_valid": true  →  "still_valid": false
```

**Adding a new relationship:**
```json
// In graph/relationships.json, append:
{
  "id": "rel-036",
  "from_id": "actor-006",
  "to_id": "dec-007",
  "relationship_type": "DECIDED",
  "description": "Nadia initiated the AI finance evaluation decision",
  "strength": "primary",
  "created_at": "2025-10-01"
}
```

---

## Schema Reference

### Valid Relationship Types

`OWNS` | `DECIDED` | `AFFECTS` | `COMMITTED_TO` | `PRODUCES` | `TOUCHES` | `REPORTS_TO` | `BLOCKS` | `DEPENDS_ON` | `SUPERSEDES` | `CREATED_BY` | `PARTICIPATED_IN`

See `schema/relationships.json` for valid source/target combinations per type.

### Valid Commitment Statuses

`open` | `fulfilled` | `broken` | `overdue` | `at_risk` | `cancelled`

### Valid Value Object Health Statuses

`healthy` | `stable` | `at_risk` | `degraded` | `expanding` | `critical` | `unknown`

### Valid Job Families

`Executive Leadership` | `Engineering` | `Product` | `Customer Success` | `Sales` | `Finance` | `People Operations` | `Marketing` | `Legal` | `Design` | `Data` | `Operations` | `Other`

---

## Connecting Sentra as a Live Data Source

The JSON files in `graph/` are manually maintained. For a production deployment, Sentra replaces them as the live data source:

- Sentra auto-extracts commitments from Slack, email, and Salesforce
- Sentra auto-extracts decisions from meeting transcripts
- The manually curated rationale, pain points, and AI assessments remain human-authored
- A sync script (`scripts/sync-from-sentra.sh`) regenerates the JSON files from Sentra's API

See `sentra/entity-mapping.md` for how Veridian's entities map to Sentra's model.
See `sentra/integration-guide.md` for step-by-step setup instructions.

---

## Demo Talking Points for Client Presentations

If you're using this repo in a client demo, here are the most compelling query sequences:

**1. The Commitment Audit (shows institutional memory gap)**
```bash
./scripts/query.sh "Show me all broken or overdue commitments and what caused them"
```
This surfaces com-001 (Hartfield SSO, overdue), com-004 (Product roadmap, broken), com-011 (Meridian CSV export, broken) and traces each to the decisions and workflows that created the gap.

**2. The Blocking Chain (shows graph relationships)**
```bash
./scripts/query.sh "What is blocking the Hartfield SSO delivery and when was the original commitment made?"
```
This traces: sales commitment (Oct 2024) → Engineering concerns ignored → tech debt freeze (Dec 2025) → SSO blocked → CEO escalation (Mar 2026). A chain of events across 18 months, instantly surfaced.

**3. The AI Opportunity Map (shows actionable insight)**
```bash
./scripts/query.sh "Which of our workflows are most ready for AI, and what's the estimated time savings?"
```
Returns ranked list: wf-003 (spec-to-ticket, 3hrs/cycle), wf-001 (month-end close, 15-20hrs/month), wf-008 (invoice reconciliation) — with specific ROI context from the graph.

**4. The Decision Archaeology (shows the 'why')**
```bash
./scripts/query.sh "Why did we choose Salesforce and is that decision still correct?"
```
Returns the 2022 decision context, Ravi's dissent, and a note that the rationale (investor optics) may be less relevant now that Series B is closed.

**5. The Risk Summary (executive view)**
```bash
./scripts/query.sh "What are the top 3 risks to our Series C story right now?"
```
Synthesizes: Hartfield at-risk account, tech debt narrative, and the self-serve competitive gap — all drawn from graph data.
