# Veridian Company Graph

A structured, agent-queryable representation of how Veridian — a fictional B2B SaaS company — actually works. Built by Vibrana to demonstrate the **Company Graph v2** concept: a living institutional memory that captures not just *what* a company does, but *why*.

Ask it anything. "What are our open customer commitments?" "Why did we kill the AI pilot?" "What's blocking Hartfield?"

---

## What Is a Company Graph?

Most companies store their institutional knowledge in three places: people's heads, Notion pages nobody reads, and meeting recordings nobody watches. When someone leaves, that knowledge walks out the door. When a commitment is made in a sales call, there's no guarantee anyone else ever knows about it.

A Company Graph changes this. It's a structured data model of the six entities that define how an organization operates:

| Entity | What it captures |
|---|---|
| **Actors** | People and teams — roles, tools, workflows, reporting structure |
| **Workflows** | How work gets done — steps, tools, pain points, AI readiness |
| **Decisions** | Key choices — with full rationale, alternatives, and dissenting views |
| **Commitments** | Promises made — to customers, internally, to the board — tracked by status |
| **Value Objects** | What the company creates and owns — products, customers, data assets |
| **Relationships** | The edges that connect everything — who owns what, what affects what |

The result is a graph you can query in natural language: "What decisions affect our Hartfield account?" "Which workflows are AI-ready?" "Show me every broken commitment."

---

## Demo Company: Veridian

This graph is seeded with data for **Veridian** — a fictional 150-person B2B SaaS company that builds workflow automation tools for mid-market finance teams.

- **Founded:** 2018 | **Stage:** Series B (£38M raised November 2023) | **HQ:** London + remote
- **ARR:** £8.2M | **NRR:** 112% | **Active customers:** 89 | **Team:** 150 people across 6 time zones
- **Core product:** Finance workflow automation platform
- **Key problem:** Classic institutional memory failure — undocumented decisions, broken customer commitments no one tracks, and AI pilots that fizzled without anyone knowing why

The demo data is intentionally rich: real-sounding names, specific pound amounts, documented disagreements, and commitments that are actively broken. It's designed to make the query experience compelling and recognizable to enterprise leadership teams.

---

## Quickstart

### Prerequisites

- `jq` — install with `brew install jq`
- `ANTHROPIC_API_KEY` — for the query interface

```bash
brew install jq
export ANTHROPIC_API_KEY=sk-ant-...
```

### Get a Summary

```bash
./scripts/stats.sh
```

Prints entity counts, commitment status breakdown, top AI-candidate workflows, and value object health. No API key required.

### Query the Graph

```bash
./scripts/query.sh "What are our open customer commitments?"
./scripts/query.sh "Which workflows are most ready for AI?"
./scripts/query.sh "Why did we kill the CS triage AI pilot?"
./scripts/query.sh "What is blocking the Hartfield SSO delivery?"
```

### Validate the Data

```bash
./scripts/validate.sh
```

Checks JSON syntax, ID format, cross-references, and business logic. Use this after any edits.

---

## What's in the Graph

### Actors (20)

The Veridian leadership team and key individual contributors — from CEO Sarah Chen and CTO Marcus Webb to VP Engineering Oliver Mwangi, Head of Marketing Sophie Laurent, and Financial Controller Kwame Asante. Each actor includes their tools, workflows, reporting structure, and qualitative notes about their role in the organization's story.

### Workflows (18)

Across every function:
- Finance: Month-End Close (38 hrs/month, high AI opportunity), Invoice Reconciliation
- Engineering: Code Review, Sprint Planning, Incident Response
- CS: Ticket Triage, Customer Onboarding, Contract Renewal
- Product: Spec to Ticket, QBR Prep
- Sales: New Business, Handoff to CS
- Legal: Security & Compliance Review (new — legal turnaround is the #1 deal-slippage driver)
- Marketing: Campaign Performance Review (new — attribution broken due to HubSpot/Salesforce split)
- People: New Employee Onboarding (new — docs last updated 2024)
- Leadership: Quarterly Planning, Annual Strategy

Every workflow includes AI readiness scores (1–10), specific pain points, and an AI opportunity summary.

### Decisions (12)

The decisions that shaped how Veridian operates — each with full rationale, alternatives considered, and documented dissent:

- Why they chose Salesforce over HubSpot (and why Sales disagreed)
- Why they killed an AI pilot for CS triage in 2024
- Why customer onboarding was moved back to CS (a decision partially reversed by dec-012)
- Why they standardized on Linear over Jira
- Why they delayed self-serve (a CEO vs. Head of Product debate still running)
- Why the COO was hired externally, bypassing two internal candidates
- Why they froze all feature development in Q1 2026 to pay down tech debt
- Why a commitment tracking system was scoped and then deferred (now recognized as a mistake)
- **New:** Why VP Engineering was hired externally instead of promoting Yuki (Marcus strongly opposed it)
- **New:** Why HubSpot and Salesforce were adopted as a split stack (attribution never worked)
- **New:** Why a dedicated Head of Customer Onboarding role was created, partially reversing dec-003

### Commitments (14)

A mix of customer, internal, and board-level commitments at various stages:

| Status | Count |
|---|---|
| Open | 8 |
| Fulfilled | 2 |
| Broken | 3 |
| Overdue | 1 |
| At Risk | 1 |

Critical open items include a CEO-level personal commitment to Hartfield Group's CFO, a Series C financial model due April 30, and a new HubSpot-Salesforce attribution commitment with a known unscheduled dependency. Two new commitments: Oliver Mwangi's runbook coverage promise to Marcus (broken), and Sophie Laurent's attribution commitment to Sarah (open, at risk).

### Value Objects (9)

- **Veridian Platform** — the core SaaS product (stable, 89 customers, £8.2M ARR)
- **Finance Workflow Engine** — the most-used module (degraded, 34% test coverage)
- **Hartfield Group** — largest customer by ARR, at-risk due to SSO commitment breach
- **Meridian Capital** — expanding customer with two untracked commitment risks
- **Solaris Financial** — recently renewed, dedicated CSM still unassigned
- **Customer Data Platform** — internal data infrastructure owned by Dev Anand
- **Engineering Runbook Library** — degraded, 60% coverage, being remediated
- **Sales Commitment Log** — Chloe Beaumont's personal Notion doc (the single point of failure)
- **Series B Funding** — £38M raised, 28 months runway, targeting Series C in H2 2026 at £12M+ ARR

### Relationships (65)

Explicit edges covering: ownership chains, reporting lines, decision-to-workflow effects, commitment blockers, data flow between workflows, and the causal chain from a 2023 hiring decision to a 2026 engineering org dynamic.

---

## Key Stories the Graph Tells

### The Hartfield Crisis

Ravi Patel committed to SSO integration in October 2024 without consulting Engineering. James Okafor flagged timeline concerns. Marcus Webb announced the Q1 2026 tech debt freeze in December 2025, blocking SSO. Sarah Chen made a personal commitment to Hartfield's CFO in March 2026 — which Engineering doesn't know about. Chloe Beaumont is managing the relationship. There is no plan.

Query: `"What is the full story of the Hartfield SSO commitment?"`

### The Broken Commitment Pattern

Three commitments were made without Engineering knowledge. A commitment tracking system was proposed, scoped, and deferred in June 2025. Fatima Al-Rashid now considers this one of the company's top three operational risks. The de facto tracking system is a personal Notion document maintained by one person.

Query: `"Why do we keep breaking commitments and what should we do about it?"`

### The AI Opportunity Map

Eight of Veridian's 18 workflows score 7+ on AI readiness. The top candidates — invoice reconciliation, spec-to-ticket generation, month-end close, and the new security questionnaire workflow — collectively represent 50–70 hours of automatable work per month. The one previous AI pilot (CS triage) failed due to the wrong tool and no change management, leaving Amara Diallo and Priya Sharma wary.

Query: `"Where should we start with AI and why?"`

### The Engineering Org Tension

Sarah Chen hired Oliver Mwangi as VP Engineering in 2023 over Marcus Webb's strong objection — Marcus wanted to promote Yuki Tanaka and considered the external hire a trust violation. Yuki now reports to Oliver. Oliver broke his first major commitment to Marcus (runbook coverage by Q1 2026). The dynamics this created are a retention risk for Yuki.

Query: `"What is the engineering org situation and what are the retention risks?"`

### The Attribution Black Hole

Sophie Laurent joined with a HubSpot preference. The company adopted a split HubSpot/Salesforce stack in 2022 to accommodate her. The sync has never worked cleanly. Marketing ROI is unmeasurable. Sophie committed to fix it by Q2 2026. The engineer who needs to do the work (Ben Osei) hasn't been told.

Query: `"Why can't we measure marketing ROI and what's the plan to fix it?"`

---

## File Structure

```
company-graph-demo/
├── README.md                    This file
├── CLAUDE.md                    Instructions for Claude Code agents
├── schema/
│   ├── entities.json            JSON Schema (draft-07) for all 6 entity types
│   └── relationships.json       Allowed relationship types + validation rules
├── graph/
│   ├── actors.json              20 people and teams
│   ├── workflows.json           18 business processes
│   ├── decisions.json           12 key decisions with full rationale
│   ├── commitments.json         14 commitments (open, fulfilled, broken)
│   ├── value-objects.json       11 products, customers, assets
│   └── relationships.json       65 explicit edges
├── scripts/
│   ├── validate.sh              Validate graph integrity
│   ├── stats.sh                 Print graph summary
│   └── query.sh                 Natural language query via Claude API
├── .claude/
│   └── settings.json            Claude Code agent permissions
└── sentra/
    ├── sync.sh                  Main sync script — pulls from Sentra API
    ├── entity-mapping.md        How our schema maps to Sentra's 6 entities
    ├── integration-guide.md     Steps to connect Sentra as live data source
    └── mock-responses/
        ├── decisions.json       Sample Sentra API decisions response
        └── commitments.json     Sample Sentra API commitments response
```

---

## From Demo to Production

This repo demonstrates the Company Graph concept with manually curated data. A production deployment replaces the JSON files with a live data source — specifically [Sentra](https://sentra.app), which auto-extracts organizational entities from Slack, Google Workspace, Linear, and other tools.

The key insight: **Sentra provides the observational layer** (what happened, who said what) while the Company Graph provides **the interpretive layer** (why it happened, what it means, what's at risk). Both are required for institutional memory that actually works.

See:
- [`sentra/sync.sh`](sentra/sync.sh) — run `./sentra/sync.sh --mock` to test the pipeline
- [`sentra/entity-mapping.md`](sentra/entity-mapping.md) — how the schemas align
- [`sentra/integration-guide.md`](sentra/integration-guide.md) — step-by-step setup

---

## Built By

[Vibrana](https://vibrana.ai) — an AI transformation consultancy that helps enterprise organizations build structured institutional memory and identify where AI creates the highest leverage.

This demo repo is part of Vibrana's **AI Readiness Assessment** deliverable. For questions, contact your Vibrana engagement lead.
