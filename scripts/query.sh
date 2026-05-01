#!/usr/bin/env bash
# query.sh — Natural language query interface for the Company Graph
# Usage: ./scripts/query.sh "What are our open customer commitments?"
# Requirements: jq, curl, ANTHROPIC_API_KEY set in environment
#
# Examples:
#   ./scripts/query.sh "What are our open customer commitments?"
#   ./scripts/query.sh "Which workflows are most ready for AI?"
#   ./scripts/query.sh "Why did we kill the CS triage AI pilot?"
#   ./scripts/query.sh "What decisions affect the Hartfield account?"
#   ./scripts/query.sh "Who owns the Finance Workflow Engine?"
#   ./scripts/query.sh "What is blocking the Hartfield SSO delivery?"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRAPH_DIR="$REPO_ROOT/graph"

# ─── Input validation ─────────────────────────────────────────────────────────
if [ -z "${1:-}" ]; then
  echo "Usage: ./scripts/query.sh \"your question here\""
  echo ""
  echo "Example questions:"
  echo '  "What are our open customer commitments?"'
  echo '  "Which workflows are most ready for AI automation?"'
  echo '  "Why did we kill the CS triage AI pilot?"'
  echo '  "What decisions affect the Hartfield account?"'
  echo '  "Who owns the Finance Workflow Engine?"'
  echo '  "What is blocking delivery of the Hartfield SSO?"'
  echo '  "Show me all broken or overdue commitments"'
  echo '  "What are the top risks to our Series C story?"'
  exit 1
fi

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "Error: ANTHROPIC_API_KEY is not set."
  echo "Set it with: export ANTHROPIC_API_KEY=sk-ant-..."
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed."
  echo "Install with: brew install jq"
  exit 1
fi

QUESTION="$1"

# ─── Load graph data ──────────────────────────────────────────────────────────
echo "Loading graph data..." >&2

ACTORS=$(jq -c '.' "$GRAPH_DIR/actors.json")
WORKFLOWS=$(jq -c '.' "$GRAPH_DIR/workflows.json")
DECISIONS=$(jq -c '.' "$GRAPH_DIR/decisions.json")
COMMITMENTS=$(jq -c '.' "$GRAPH_DIR/commitments.json")
VALUE_OBJECTS=$(jq -c '.' "$GRAPH_DIR/value-objects.json")
RELATIONSHIPS=$(jq -c '.' "$GRAPH_DIR/relationships.json")

# ─── Build system prompt ──────────────────────────────────────────────────────
SYSTEM_PROMPT="You are the Company Intelligence Assistant for Veridian — a 75-person B2B SaaS company that builds workflow automation tools for mid-market finance teams (Series B, £22M raised, headquartered in London).

You have access to Veridian's complete Company Graph: a structured representation of the company's people, workflows, decisions, commitments, and value objects. This graph captures not just what the company does, but why — including decision rationale, dissenting views, and the history of how the company got to its current state.

Your role is to answer questions from Veridian's leadership team (CEO, COO, function heads) in a clear, direct, and actionable way. You:
- Surface hidden connections between entities (e.g., how a decision made in 2022 is blocking a customer commitment in 2026)
- Flag risks that aren't obvious from any single data source
- Reference specific entity IDs (actor-001, wf-003, dec-008, etc.) when relevant so people can look up full details
- Are honest about uncertainty or gaps in the data
- Prioritize business impact in your answers — a CEO wants to know what to do, not just what's in the data

When answering:
1. Lead with the direct answer to the question
2. Provide supporting context from the graph
3. Flag any related risks or connections that the person asking should be aware of
4. Suggest a follow-up action where appropriate

Format responses clearly with headers or bullets where it improves readability. Keep answers concise but complete — typically 150–400 words unless the question requires a comprehensive list."

# ─── Build user message with graph context ────────────────────────────────────
USER_MESSAGE="Here is the complete Company Graph data for Veridian. Please answer my question using this data.

## ACTORS
$ACTORS

## WORKFLOWS
$WORKFLOWS

## DECISIONS
$DECISIONS

## COMMITMENTS
$COMMITMENTS

## VALUE OBJECTS
$VALUE_OBJECTS

## RELATIONSHIPS
$RELATIONSHIPS

---

My question: $QUESTION"

# ─── Call Claude API ──────────────────────────────────────────────────────────
echo "Querying graph..." >&2
echo "" >&2

# Build the JSON payload using jq to ensure proper escaping
PAYLOAD=$(jq -n \
  --arg model "claude-sonnet-4-6" \
  --arg system "$SYSTEM_PROMPT" \
  --arg user_msg "$USER_MESSAGE" \
  '{
    model: $model,
    max_tokens: 1500,
    system: $system,
    messages: [
      {
        role: "user",
        content: $user_msg
      }
    ]
  }')

RESPONSE=$(curl -s \
  --max-time 60 \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "$PAYLOAD" \
  "https://api.anthropic.com/v1/messages")

# ─── Parse and display response ───────────────────────────────────────────────
ERROR=$(echo "$RESPONSE" | jq -r '.error.message // empty' 2>/dev/null || true)
if [ -n "$ERROR" ]; then
  echo "API Error: $ERROR" >&2
  echo "Full response: $RESPONSE" >&2
  exit 1
fi

ANSWER=$(echo "$RESPONSE" | jq -r '.content[0].text // "No response received"')

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Q: $QUESTION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "$ANSWER"
echo ""

# Optionally show token usage
USAGE=$(echo "$RESPONSE" | jq -r '"Tokens used: \(.usage.input_tokens) in + \(.usage.output_tokens) out"' 2>/dev/null || true)
if [ -n "$USAGE" ]; then
  echo "[$USAGE]" >&2
fi
