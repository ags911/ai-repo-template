---
name: adr-builder
description: Draft an Architecture Decision Record in docs/adr/ with status Proposed and add it to the decision index. Use when a significant change needs its decision recorded, when the user asks to write or draft an ADR, or after a trade-off analysis recommends one.
---

# ADR builder

Produces one new ADR file with status **Proposed** and one new row in the decision index.

## Preconditions
- `docs/adr/README.md` (the index) and `docs/adr/0000-template.md` exist. If either is
  missing, stop and say the `adr` module is not installed. Do not create them yourself.
- You know what is being decided. If a trade-off analysis was done in this conversation,
  use its options, costs, and recommendation as the source; do not redo it.

## Procedure
1. **Read the index** `docs/adr/README.md`. Open individual ADRs only if they cover the same
   area as this decision (to find one this ADR might supersede or contradict).
2. **Take the next number.** Find the highest number among the index rows *and* the
   `docs/adr/NNNN-*.md` filenames (they can drift apart). Next number = highest + 1, padded
   to four digits. Never reuse a number, even if a file was deleted.
3. **Check the options.** List the real options: ones the team could actually choose,
   including "do nothing" only if it is viable. If there are fewer than two, stop and ask the
   user before writing anything. Say which option(s) you found and ask whether an
   alternative was considered or whether this belongs in a commit message instead of an ADR.
4. **Write** `docs/adr/NNNN-short-kebab-title.md` by copying `0000-template.md` and filling
   every section:
   - Title line: `# ADR NNNN: <title>`.
   - `Status: Proposed`. Never write `Accepted`, even if the user says the decision is made.
     Accepting is a human edit to the file.
   - `Date:` today, `YYYY-MM-DD`.
   - `Deciders:` name the human who will accept it if known, otherwise `TBD (drafted by an agent)`.
   - Context: the forces in two or three sentences, with file paths or issue links as evidence.
   - Options considered: every real option from step 3, one short paragraph each.
   - Decision: the recommended option, phrased as proposed ("We propose ...").
   - Why, and what it costs: name which qualities get better and which get worse.
   - Consequences: new dependencies, migrations, follow-up work, and what would make this
     decision worth revisiting.
   Delete template placeholder text; leave no `NNNN` or `YYYY-MM-DD`.
5. **Supersession.** If this ADR replaces an existing one, say so in Context
   (`Supersedes ADR-XXXX`). Do not change the old ADR's status. List it under "Needs a human"
   in your output so a person updates it when they accept this one.
6. **Add the index row** to the table in `docs/adr/README.md`, in number order:
   `| [NNNN](NNNN-short-title.md) | <title> | Proposed |`, linking the new file. Change
   nothing else in the index.

## Output
Reply with:
- the new file path and the index row you added;
- **Open questions**: anything you had to guess (owner, dates, option details);
- **Needs a human**: accepting the ADR, and any ADR it supersedes.
