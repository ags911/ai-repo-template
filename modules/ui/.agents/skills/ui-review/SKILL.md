---
name: ui-review
description: Review a user-interface change by looking at it. Captures every state at desktop and phone width, runs the layout guards, and reads the screenshots against docs/ui-checklist.md. Use after any UI change and before saying UI work is done, when asked to review a screen, drawer, form, layout, spacing, buttons, responsive behaviour or UX, or when a reviewer needs screenshots.
---

# UI review

A passing test and a clean accessibility scan do not show that a screen looks right. A button
with no padding, a control stranded at the far edge of a row, and a sentence shown twice all
pass both. This skill makes the reviewer look.

Suggested model and effort: a model that reads images, medium effort. It edits no files unless
the user asks for fixes.

## Procedure
1. **Capture.** Run the project's screens spec (`npx playwright test screens`, from
   `tests/e2e/screens.spec.ts`). It writes one screenshot per state and width to the
   test output folder and runs the layout guards. If a state the change touches has no entry,
   add one first: a UI review of states nobody captured reviews nothing.
2. **Read the guards.** A failed guard is a finding. Quote its message. Do not loosen a guard.
3. **Look at every image.** Open each screenshot, desktop first, then phone. Go through
   `docs/ui-checklist.md` item by item for each image. Do not summarise from the file names.
4. **Check computed styles when something looks off.** Layout bugs are often CSS precedence,
   not markup (an unlayered global reset beats every utility class). Read the element's computed
   padding, size and position before proposing a fix, and fix the cause, not one instance.
5. **Report**, most severe first. For each finding: the state and width, what is wrong, the
   evidence (screenshot name or guard message), and the smallest fix. Say what you checked
   and found fine, so the reader knows the review had coverage.

## What it does not do
- It does not judge brand or visual taste; it checks the checklist.
- It does not replace the owner looking at the real screen before release.
- Baseline-image comparison is a separate decision (see `modules/README.md`, ui).
