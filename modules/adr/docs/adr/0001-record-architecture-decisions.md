# ADR 0001: Record architecture decisions

- **Status:** Accepted
- **Date:** YYYY-MM-DD
- **Deciders:** repository owner

## Context
Agents and people both change this codebase. Without a record, decisions get silently
reversed or re-argued.

## Decision
Record significant decisions as ADRs in `docs/adr/` and list each in `docs/adr/README.md`.
"Significant" matches the Significant row in AGENTS.md.

## Why, and what it costs
Costs a few minutes per significant change. Buys a durable reason that survives
turnover and context-window limits.

## Consequences
Agents propose ADRs with status Proposed. Only a human sets Accepted.
