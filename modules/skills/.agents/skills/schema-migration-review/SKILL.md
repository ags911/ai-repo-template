---
name: schema-migration-review
description: Plan a database schema, event payload, or API contract change so it never breaks code that is already running, as expand, migrate and contract steps across releases, with a rollback for each step. Use before renaming or dropping a column, changing a field's type, splitting a table, or changing an event or API payload, or when the user asks whether a schema change is safe.
---

# Schema migration review

Produces a release-by-release plan for one change to stored data or a contract that other
code reads, so every release works with both the old and the new shape while it rolls out.

Suggested model and effort: most capable model, high effort. A wrong step loses data.

## Preconditions
- You know the change (for example "rename `orders.qty` to `orders.quantity`") and where the
  shape is defined: migrations folder, ORM models, event schemas, OpenAPI files. Find them
  before planning. If you can't, stop and ask.
- You know who reads and writes the shape: services, jobs, other repos, analytics. Search
  the code for the name. List readers you can't see (other repos, dashboards) as unknowns.

## Procedure
1. **Classify the change.** Additive (new optional column or field), breaking (rename, drop,
   type change, new required field, meaning change), or both. Additive changes still need a
   default for existing rows and must tolerate old writers.
2. **Check what's running.** Old and new code run side by side during a deploy, and old code
   can come back on rollback. Any step must work with the previous release's code.
3. **Split into steps**, each its own release:
   - **Expand:** add the new shape beside the old one. Nothing reads it yet. Writers write
     both, or a trigger or backfill keeps them in step.
   - **Migrate:** backfill existing data in batches; switch readers to the new shape, then
     writers. Verify counts or checksums match between old and new.
   - **Contract:** remove the old shape only when no running code, job or reader uses it.
   Never rename or drop in one step; a rename is expand plus migrate plus contract.
4. **For each step, write:** the change (migration file or code change), how to roll it back
   without losing data written since, and what must be true before the next step starts
   (all instances on the new release, backfill finished, old field unused for N days, logs
   or metrics that prove it).
5. **Check the contract step's preconditions are observable.** "No readers left" needs
   evidence: a search result, a metric, a deprecation log. If there is none, say so.
6. If the plan adds a dependency or changes a public contract, it is a Significant change in
   AGENTS.md: recommend recording it as an ADR.

## Output
Reply with:
- **Change:** one line, and whether it is additive, breaking, or both.
- **Readers and writers:** the ones found (with paths) and the unknowns.
- **Steps:** a numbered list, one per release: change, rollback, and before-next-step check.
- **Risks:** what could still lose or corrupt data, and how the plan limits it.
- **Needs a human:** decisions you couldn't make (deadline for the contract step, unknown
  readers, an ADR).
