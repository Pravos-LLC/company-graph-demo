# Sentra Entity Mapping — Veridian Company Graph

This document maps Veridian's 6 Company Graph entity types to Sentra's 6-entity organizational memory model, explaining what each system captures, how the schemas align, and which data Sentra auto-populates versus what requires manual seeding.

---

## Entity Mapping Table

| Veridian Entity | Sentra Entity | Alignment | Notes |
|---|---|---|---|
| **Actor** | **Actor** | Direct | Same concept. Sentra auto-populates from connected directory/HR systems. |
| **Workflow** | **Interaction** | Partial | Sentra captures individual interaction instances; Veridian generalizes to workflow patterns. |
| **Decision** | **Decision** | Direct | Same concept. Sentra extracts from meeting transcripts and documents. |
| **Decision.rationale** | **Rationale** | Sub-entity | Veridian embeds rationale inside Decision; Sentra treats it as a separate linked entity. |
| **Commitment** | **Commitment** | Direct | Same concept. Sentra extracts from email and Slack; Veridian seeds manually. |
| **ValueObject** | **Value-Creating Object** | Direct | Same concept. Sentra infers from document mentions; Veridian seeds explicitly. |
| **Relationship** | *(implicit edges)* | Structural | Sentra manages edges natively in its graph store; Veridian externalizes them in relationships.json. |

---

## Detailed Mapping by Entity

### Actors → Sentra Actors

**What matches:**
Sentra's Actor entity captures `name`, `role`, `team`, `tools`, and organizational hierarchy. This maps directly to Veridian's Actor schema including `role`, `job_family`, `reports_to`, and `tools_used`.

**What Sentra auto-populates:**
- Identity from Google Workspace or Slack directory
- Role from HR system (Rippling integration)
- Tool usage inferred from OAuth-connected app activity
- Reporting structure from Google Workspace org chart

**What requires manual seeding:**
- `current_workflows` — Sentra doesn't model repeatable workflow patterns, only interaction instances
- `notes` — Qualitative context about an actor's history, skepticism, or informal influence
- `joined_date` — Must be synced from Rippling or HR system

**Schema difference:** Sentra's Actor may include communication patterns (average response time, active hours) inferred from Slack. Veridian's schema doesn't currently capture this but should be added.

---

### Workflows → Sentra Interactions

**What matches:**
Sentra's Interaction entity represents a discrete event (a meeting, a document creation, a Slack thread). Veridian's Workflow represents the *pattern* — the repeatable process that many Interaction instances constitute.

**The gap:** This is the most significant schema difference. Sentra doesn't natively model repeatable process patterns — it surfaces individual instances. To bridge this:

- Veridian's `workflow.json` entries remain manually curated (the process definition)
- Sentra provides the *evidence* that a workflow is happening — the actual meeting records, documents, and communication patterns
- A Sentra export query can pull all Interactions tagged to a workflow category and hydrate the `steps[]` and `tools_used[]` fields over time

**What Sentra auto-populates:**
- Instances of workflow execution (meeting: "Month-End Close review", document: "February P&L")
- Participants in each workflow instance
- Tools used in each instance (via Slack integrations and document metadata)

**What requires manual seeding:**
- Workflow definitions (trigger, output, steps, pain_points)
- `ai_readiness_score` and `ai_candidate` — these are assessments, not observations
- `avg_time_hours` — must be estimated or measured separately

---

### Decisions → Sentra Decisions

**What matches:**
This is the most direct mapping. Sentra's Decision entity is structurally identical to Veridian's. Both capture: decision description, maker(s), date, context, and outcomes.

**What Sentra auto-populates:**
- Decision text extracted from meeting transcripts (requires meeting transcription via Zoom or Google Meet)
- Decision makers inferred from participants and speaking patterns
- Date from transcript metadata
- Links to source documents and Slack threads where the decision was discussed

**What requires manual seeding (initially):**
- `alternatives_considered` — Sentra may surface alternatives mentioned in transcripts, but structured capture of rejected options requires human review
- `rationale` — Deep rationale is rarely stated explicitly in meetings; requires interview or document annotation
- `dissenting_views` — Often expressed informally or not at all in recorded meetings; requires deliberate capture process
- `still_valid` — A retrospective judgment that must be made by a human

**Sentra-specific enrichment:**
Sentra can surface the *trail* of discussions that led to a decision — the Slack threads, the pre-reads, the side conversations. This contextual network is not captured in Veridian's JSON structure but is accessible via the Sentra API.

---

### Decision.rationale → Sentra Rationale

**What matches:**
Sentra models Rationale as a first-class entity, separate from Decision. This is architecturally cleaner than Veridian's approach (rationale embedded as a field inside Decision).

**What Sentra auto-populates:**
- Rationale fragments extracted from documents, emails, and meeting transcripts associated with the decision
- Confidence scores for extracted rationale (how clearly stated it was)

**What requires manual seeding:**
- Structured rationale as written in Veridian's `decisions.json` — this is typically more complete and deliberate than what Sentra can auto-extract
- For legacy decisions (pre-Sentra), all rationale must be seeded manually

**Migration recommendation:** When connecting Sentra, export existing `decisions[].rationale` fields and ingest them as Sentra Rationale entities linked to their parent Decisions. This preserves institutional memory that Sentra cannot retroactively discover.

---

### Commitments → Sentra Commitments

**What matches:**
Sentra's Commitment entity maps closely to Veridian's. Both track: who made the commitment, to whom, what was promised, and the status.

**What Sentra auto-populates:**
- Commitment text extracted from email and Slack (e.g., "I'll have that to you by Friday")
- Commitment maker inferred from message sender
- Due dates extracted from natural language date references
- Status inferred by looking for confirmation messages after due date

**The gap:** Sentra's auto-extraction works well for informal commitments in communication tools. Veridian's most important commitments (customer promises in sales calls, contract addenda) live in Salesforce and DocuSign — not email or Slack. These require a Salesforce connector or manual entry.

**What requires manual seeding:**
- Formal customer commitments from Salesforce opportunity notes
- Contract-level commitments from DocuSign/legal documents
- `priority` classification
- `evidence_source` — the specific document or message where it's captured

**Critical gap for Veridian:** The Hartfield SSO commitment (com-001) was made verbally on a call and noted in Salesforce — not in Slack or email. Sentra would not auto-discover this. This class of commitment must be manually seeded and is precisely the institutional memory gap the graph is designed to solve.

---

### ValueObjects → Sentra Value-Creating Objects

**What matches:**
Sentra's Value-Creating Objects represent outcomes, products, and assets the organization produces or maintains. This maps to Veridian's `ValueObject` entity.

**What Sentra auto-populates:**
- Products and features mentioned frequently in internal documents
- Customers mentioned in communication patterns
- Projects inferred from Linear or GitHub activity

**What requires manual seeding:**
- Formal classification (`type`: product / customer / data asset / capital asset)
- `business_value` — a qualitative or financial statement that requires human judgment
- `health_status` — a deliberate assessment, not an observable metric
- Internal knowledge assets (runbook library, commitment log) that aren't prominently mentioned in communication tools

---

## Auto-Populate vs. Manual Seed — Summary

| Field | Sentra Auto-Populates? | Notes |
|---|---|---|
| Actor identity, role, team | Yes | Requires Google Workspace + Rippling connectors |
| Actor tools used | Partial | Inferred from OAuth apps; not comprehensive |
| Workflow definitions | No | Must be manually authored |
| Workflow pain points | No | Human assessment |
| AI readiness scores | No | Human assessment |
| Decision text | Yes (from transcripts) | Requires meeting transcription |
| Decision rationale | Partial | Surface-level; deep rationale needs human input |
| Decision dissenting views | No | Rarely explicit in transcripts |
| Informal commitments | Yes | Slack/email extraction |
| Formal customer commitments | No | Requires Salesforce connector or manual entry |
| Commitment status | Partial | Infers fulfillment from follow-up messages |
| Product/customer as value objects | Partial | Infers from mention frequency |
| Business value of value objects | No | Human judgment |
| Health status | No | Human assessment |
| Relationship edges | Partial | Infers co-occurrence; not causal structure |

**Rule of thumb:** Sentra provides the *observational* layer (what happened, who talked to whom, what was said). Veridian's graph provides the *interpretive* layer (why it happened, what it means, what should be done). Both are required for a complete picture.

---

## Recommended Integration Approach

1. **Phase 1 — Manual seed** (this repo): Establish the interpretive layer with rich, high-quality data about the company's key entities. This is the starting point.

2. **Phase 2 — Connect Sentra**: Wire Sentra to Slack, Google Workspace, Linear, and Salesforce. Let Sentra begin building the observational layer.

3. **Phase 3 — Sync**: Build a scheduled export from Sentra's API that hydrates or validates the manually-curated entities. New commitments discovered by Sentra are flagged for human review and promotion to `commitments.json`.

4. **Phase 4 — Live graph**: The Company Graph is continuously updated by Sentra, with humans retaining editorial control over decisions, rationale, and assessments.

See `integration-guide.md` for step-by-step technical setup instructions.
