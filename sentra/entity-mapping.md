# Sentra Entity Mapping — Veridian Company Graph

How Veridian's Company Graph schema maps to Sentra's 6-entity organizational memory model. This document defines what Sentra auto-populates, what requires manual input, how confidence scores drive the import pipeline, and how conflicts between Sentra and the manual graph are resolved.

---

## 1. Entity Mapping Table

| Veridian Entity | Sentra Entity | Alignment | Notes |
|---|---|---|---|
| **Actor** | **Actor** | Direct | Same concept. Sentra auto-populates identity, role, and tool usage from connected directory/HR systems. |
| **Workflow** | **Interaction** | Partial | Sentra captures individual event instances; Veridian generalizes to repeatable process patterns. Manual authorship required for workflow definitions. |
| **Decision** | **Decision** | Direct | Highest-value mapping. Sentra extracts from meeting transcripts and Slack. Rationale and dissenting views require human completion. |
| **Decision.rationale** | **Rationale** | Sub-entity | Veridian embeds rationale inside Decision; Sentra treats it as a linked entity. Export rationale manually when seeding Sentra. |
| **Commitment** | **Commitment** | Direct | Strong mapping. Sentra extracts informal commitments from Slack and email well; formal customer commitments from Salesforce require the Salesforce connector or manual seeding. |
| **ValueObject** | **Value-Creating Object** | Partial | Sentra infers from mention frequency. Classification, business value, and health status require human judgment. |
| **Relationship** | *(implicit graph edges)* | Structural | Sentra manages edges natively. Veridian externalizes them in `relationships.json`. The sync script does not import relationships — they are manually authored. |

---

## 2. Field-Level Mapping: What Sentra Auto-Populates vs. Manual

### Actors

| Veridian Field | Sentra Auto-Populates? | Source | Manual Input Required |
|---|---|---|---|
| `name` | Yes | Google Workspace / Slack directory | No |
| `role` | Yes | Rippling HR or Workspace title | Verify on changes |
| `job_family` | Partial | Inferred from department | Map to Veridian job families |
| `tools_used` | Partial | OAuth-connected apps; incomplete | Complete with less-visible tools |
| `reports_to` | Yes | Google Workspace org chart | No |
| `joined_date` | Yes | Rippling HR | No |
| `location` | Yes | Workspace profile | No |
| `current_workflows` | No | Sentra models instances, not patterns | Manual — requires understanding which workflows the actor is involved in |
| `notes` | No | Qualitative context can't be inferred | Manual — the most important field for demo quality |

### Workflows

Workflows are **entirely manually authored** in Veridian's schema. Sentra surfaces interaction instances (meeting: "Sprint Planning — March 25", Slack thread: "#incident-20260312") that can be used to enrich or verify workflow definitions, but the process abstraction itself requires human judgment.

| Veridian Field | Sentra Auto-Populates? | Notes |
|---|---|---|
| `name` | No | Human-authored |
| `trigger` | No | Human-authored |
| `steps` | No | Human-authored |
| `tools_used` | Partial | Sentra can surface tools mentioned in workflow-related interactions |
| `avg_time_hours` | No | Requires measurement or estimation |
| `pain_points` | No | Qualitative — requires interviews or observation |
| `ai_readiness_score` | No | Human assessment |
| `ai_candidate` | No | Human judgment |

### Decisions

Decisions are Sentra's highest-value auto-extraction target and the entity type most likely to have useful data in `sentra/mock-responses/decisions.json`.

| Veridian Field | Sentra Auto-Populates? | Confidence | Notes |
|---|---|---|---|
| `title` | Yes | High | Extracted from meeting transcript or document |
| `made_by` | Yes | Medium | Inferred from speaker/sender — verify |
| `made_at` | Yes | High | From source metadata |
| `summary` | Yes | High | LLM summary of the source excerpt |
| `context` | Partial | Low | Background context rarely stated explicitly; often requires additional interviews |
| `alternatives_considered` | Partial | Low | Surface-level only; structured capture requires human review |
| `rationale` | Partial | Medium | May be stated in source; deep rationale needs annotation |
| `dissenting_views` | Rarely | Very Low | Disagreements expressed informally or not at all in transcripts |
| `outcome` | No | — | Retrospective; human authorship only |
| `still_valid` | No | — | Human judgment |
| `affects_workflows` | No | — | Cross-entity linkage requires human knowledge |

### Commitments

| Veridian Field | Sentra Auto-Populates? | Confidence | Notes |
|---|---|---|---|
| `made_by` | Yes | High | From message sender |
| `made_to` | Yes | High | From message recipient or named party |
| `type` | Partial | Medium | Infers customer vs. internal from context |
| `description` | Yes | High | LLM summary of the commitment text |
| `due_date` | Partial | Medium | Extracted if stated; often missing from informal Slack messages |
| `status` | Partial | Low | Infers from follow-up messages; unreliable for complex commitments |
| `evidence_source` | Yes | High | Source metadata (channel, message ID, meeting title) |
| `priority` | No | — | Human judgment |
| `notes` | Partial | Low | Basic context only; rich notes are human-authored |

**Critical gap:** Customer commitments made in sales calls (e.g., com-001 Hartfield SSO, com-011 Meridian CSV export) are documented in Salesforce opportunity notes, not Slack or email. Sentra will not auto-discover these without the Salesforce connector. This class of commitment — the highest-stakes type — must be manually seeded or requires Salesforce connector configuration.

### Value Objects

| Veridian Field | Sentra Auto-Populates? | Notes |
|---|---|---|
| `name` | Partial | Inferred from frequent mentions in documents and communication |
| `type` | No | Human classification required |
| `description` | No | Human-authored |
| `business_value` | No | Financial or qualitative assessment; human judgment |
| `health_status` | No | Deliberate assessment — not an observable |
| `owner` | Partial | Inferred from who mentions/manages the object most frequently |

---

## 3. Confidence Score Thresholds

Sentra assigns a `confidence_score` (0.0–1.0) to each auto-extracted entity. The sync script uses these thresholds:

| Threshold | Behaviour | Action Required |
|---|---|---|
| **≥ 0.75** | Auto-import queue | Appended to graph with `_review_status: "pending_human_review"`. Operator assigns a sequential ID and completes `__NEEDS_HUMAN_INPUT__` fields. |
| **0.50–0.74** | Human review queue | Not auto-imported. Surfaced in Sentra UI for review. Operator decides: promote to graph (with enrichment), dismiss, or request Sentra re-extract with corrections. |
| **< 0.50** | Ignored | Entity logged but discarded. Low confidence typically means the extraction was ambiguous — often a conversational mention rather than a real decision or commitment. |

**Why 0.75?** Below this threshold, the extraction quality tends to be noisy enough that human review is faster than trying to fix a bad auto-import. Above it, the summary and key fields are usually accurate enough to serve as a starting draft.

**Adjusting thresholds:** Edit the `jq` filter in `sentra/sync.sh` (lines referencing `select(.confidence_score >= 0.75)`). If Sentra's extraction quality improves over time (as it trains on your organization's patterns), consider lowering to 0.70.

---

## 4. Conflict Resolution

When Sentra's auto-extracted data contradicts what's already in the manual graph, the following rules apply:

### Rule 1: Manual data wins on fields that require judgment

Fields like `rationale`, `dissenting_views`, `outcome`, `still_valid`, `notes`, `ai_readiness_score`, and `health_status` represent human interpretation. If a manually authored field conflicts with a Sentra inference, the manual field is authoritative and Sentra's version is stored in a `_sentra_*` prefixed field for reference.

### Rule 2: Sentra wins on observable facts

Fields like `made_at` (date extracted from source metadata), `evidence_source` (document/message reference), and `made_by` (sender identity) are directly observable. If the manual graph has an incorrect date and Sentra has the correct one from transcript metadata, update the manual record.

### Rule 3: New Sentra entities don't overwrite existing manual entities

The sync script appends new entities — it does not perform update-in-place for existing entities matched by ID. If Sentra surfaces a decision that's already in the graph (same title, same date), the operator should manually review and merge. A future version of the sync script could support `--update-existing` with explicit conflict flags.

### Rule 4: For commitments, Salesforce is authoritative over Sentra

Customer commitments where the evidence source is a Salesforce opportunity record take precedence over Sentra's Slack/email extractions. If they conflict, the Salesforce record is correct. This reflects the fact that Ravi Patel's sales commitments are captured in Salesforce, not Slack.

### Rule 5: Flag conflicts, don't silently resolve them

When a conflict is detected, the sync script prefixes the affected field with `_conflict_` and logs a warning. Example:

```json
"made_at": "2024-10-14",
"_conflict_made_at_sentra": "2024-10-16",
"_conflict_note": "Manual record says Oct 14; Sentra transcript metadata says Oct 16. Verify with Salesforce opportunity note."
```

---

## 5. Entities Sentra Won't Find (Must Be Manually Seeded)

These entity types require manual authorship and will never be auto-discovered by Sentra:

- **Workflow definitions** — the repeatable process abstraction, not an observable event
- **AI readiness scores** — analytical assessment
- **Decisions from before Sentra was connected** — no historical observability
- **Dissenting views** — rarely stated explicitly in meetings; requires deliberate documentation practice
- **Customer commitments made verbally on calls** — unless call transcription is enabled via Gong or Zoom
- **Health status assessments** — requires context that Sentra can't infer

The recommendation: treat the manually curated graph as the starting state (Phase 1), connect Sentra to augment it with observations (Phase 2), and progressively reduce the manual maintenance burden over time. The graph never becomes fully automated — the interpretive layer always requires human judgment.

---

## 6. Schema Differences to Be Aware Of

**Sentra Rationale as a separate entity:** Sentra models `Rationale` as a first-class linked entity, not a field inside Decision. When seeding Veridian's decisions into Sentra, export the `decisions[].rationale` fields and ingest them as Sentra Rationale entities linked to their parent Decisions.

**Sentra's interaction volume:** Sentra surfaces many more interaction instances than Veridian has workflows. A single workflow like "Engineering Sprint Planning" might generate 20+ Sentra interaction records per quarter (each sprint planning meeting). The sync script intentionally does not import interactions — they are accessible via the Sentra UI and API but the workflow-level abstraction is maintained manually.

**Participant vs. actor:** Sentra's `participants[]` array in decisions and commitments contains name strings, not actor IDs. The sync script maps these to `made_by: "Name"` strings. After auto-import, the operator should replace name strings with the corresponding `actor-NNN` IDs for full graph traversal to work.
