---
name: tradeoff-analyzer
description: Compare the real options for a significant change (new dependency, schema change, new module or cross-module call, public API change) against the quality attributes this project prioritises, and recommend one before any code is written. Use when a change falls in the Significant row of AGENTS.md, or when the user asks for options, trade-offs, or a recommendation.
---

# Trade-off analyzer

Produces a written proposal for one significant change: the options, what each gains and
costs, how reversible each is, a recommendation, and whether an ADR is needed. It writes no
code and edits no files.

## Procedure
1. **State the decision** in one sentence: what has to be chosen, and what forces the choice
   now (a failing requirement, a ticket, a limit being hit). Cite files or issues.
2. **Find the priorities.** Look in `ARCHITECTURE.md`, accepted ADRs in `docs/adr/`, and the
   PRD for this work (`docs/prd/`) for the quality attributes this project cares most
   about, such as latency, cost, operability, data integrity, time to ship, or testability.
   Use only the few that matter for this decision. If nothing is written down, propose the
   ones the decision seems to hinge on and ask the user to confirm or correct them before
   you continue. Do not judge options against priorities you made up.
3. **List the real options.** Include "do nothing / keep the current approach" when it is
   viable, and say why if it is not. Drop options nobody would pick, and say you dropped
   them. Check each option against the codebase: does it fit the existing layer rules in
   `ARCHITECTURE.md` and the decisions in `docs/adr/`? An option that breaks one must say so.
4. **For each option, write:**
   - **Gains**: what improves, tied to the priorities from step 2.
   - **Costs**: what gets worse or what new work it creates (dependencies to maintain,
     migrations, operational load, lock-in), tied to the same priorities.
   - **Reversibility**: what undoing it would take a year from now. Name the concrete work
     (rewrite N call sites, migrate stored data, renegotiate a vendor contract). Mark it
     *easy*, *costly*, or *one-way*.
   - **Unknowns**: anything you could not verify, and how to find out cheaply (a spike, a
     benchmark, a question for the user).
   List as many gains and costs as are true. Do not pad to a set number or trim to make
   options look balanced.
5. **Recommend one option.** Say which priorities decided it, what you are trading away,
   and what new information would change the recommendation. If the options are close
   and the deciding factor is a business judgement, say so and leave the choice to the user.
6. **Decide whether an ADR is needed.** Yes if `docs/adr/` exists and the change is
   Significant per AGENTS.md. If `docs/adr/` does not exist, say where the decision should
   be recorded instead (for example the PR description).

## Output
```
## Decision
<one sentence + what forces it now>

## Priorities used
<attribute — source (file or "confirmed by user")>

## Options
### <Option name>
- Gains: ...
- Costs: ...
- Reversibility: easy | costly | one-way — <what undoing takes>
- Unknowns: ...

## Recommendation
<option, why, what we give up, what would change this>

## ADR
<needed / not needed, and why> (if needed, offer to run adr-builder after the user chooses)
```
End by asking the user to choose. Do not start implementing in the same turn.
