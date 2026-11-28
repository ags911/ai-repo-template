---
name: design-system-audit
description: Audit a project's design system against an AI-readiness roadmap (by default the project's copy at docs/research/design-system-roadmap.md). Rates each area of the system, finds where the written rules and the code disagree, runs sample tasks to see where an AI agent would have to guess, and writes a short prioritised plan. Use when asked to audit, assess or review a design system, check whether it is AI-ready, find gaps in tokens, components or design documentation, or decide what design-system work to do next. Not for reviewing one screen (use ui-review).
---

# Design system audit

An AI agent builds UI from whatever rules it can find. If those rules are missing, scattered
or out of date, it guesses, and every guess gets repeated. This skill finds where that would
happen and turns it into a short plan. It reviews the system, not one screen.

Suggested model and effort: most capable model, high effort. Most findings come from
comparing documents with code, which takes careful reading.

## Before you start
- **The roadmap.** Read the project's roadmap reference, by default
  `docs/research/design-system-roadmap.md`. It lists the areas to rate, what each needs, and
  a readiness test per area. This skill gives the method, not the roadmap's content: if the
  project has no roadmap file, ask the user for one (for example their licensed copy of a
  published roadmap, as Markdown) and do not invent its areas from memory.
- **The system's sources.** Find every place a design decision is recorded: `DESIGN.md`,
  ADRs in `docs/adr/`, `docs/ui-checklist.md`, the token files (CSS variables, Tailwind
  theme, `tokens.json`), the component folder, the screens spec, and Figma links if any.
  Note which source each decision comes from.

## Procedure
1. **Rate each area** from the roadmap as one of:
   - *Clear*: the decision is explicit, current and findable.
   - *Partial*: it exists but is scattered, incomplete or partly out of date.
   - *Missing*: nothing is recorded, so people rely on memory and an agent would guess.
   - *Not needed now*: a real area, but premature for this project's size. Say why.
   Give evidence for every rating: a file path and what it shows. A rating without
   evidence is an opinion; leave it out.
2. **Compare the written rules with the code.** For each decision a document states (sizes,
   colours, radii, the component list, spacing), check the code and any test that asserts
   it. Record each disagreement in a table: decision, what the document says, what the code
   says, and which one a test agrees with. Do not decide which side is right; that is the
   owner's call. A document that disagrees with the code misleads agents more than a
   missing one.
3. **Look for raw values.** Search components for literal values where a token or utility
   exists or should exist (`rounded-[12px]` when a 12px radius token exists, hex colours,
   repeated letter-spacing). List the repeats, not every instance.
4. **Run readiness tests.** Write three to five realistic tasks an agent might be given
   ("add a metric card in the overview style", "colour a new status indicator", "add a
   settings drawer"). For each, say which sources an agent would read and whether they lead
   to the right result. Mark each Passes or Fails, with the reason.
5. **Plan.** Pick the three to five gaps that affect current work, block other areas, or
   cause the failed tests. One row each: area, why it matters now, owner, smallest useful
   next action, and how you will know it is done. Prefer actions that make existing
   decisions explicit over new design work.

## Output
Write the audit to `docs/research/design-system-audit.md` (or where the user asks), with:
1. A plain-English summary: what is solid, the main risk, and the recommended next steps.
2. The ratings, one table per stage, each row with evidence.
3. The drift table from step 2.
4. The readiness tests and results.
5. The plan table.

## What it does not do
- It does not change tokens, components or documents. Fixes are separate changes, and
  changing a design decision goes through the project's ADR process.
- It does not judge visual taste or brand.
- It does not give a maturity score. The plan is the result.
