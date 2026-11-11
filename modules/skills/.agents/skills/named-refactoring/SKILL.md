---
name: named-refactoring
description: Clean up messy code by naming its code smells and applying named refactorings one small, behaviour-preserving step at a time, running the tests after every step. Use when the user asks to clean up, untangle, simplify or restructure code (a long function, duplication, a class doing too much), not for a single rename or a behaviour change.
---

# Named refactoring

Produces a cleaner version of the code with the same behaviour, reached through small named
steps, and a log of each step with its test result.

Suggested model and effort: default model and effort. Each step is small and the tests
check it; raise the effort only if the code has no tests.

## Preconditions
- The code has tests that cover the behaviour you will touch. If it doesn't, stop and say so;
  offer to add characterisation tests first (tests that pin down what the code does now).
- The tests pass before you start. Run them. If they fail, stop: refactoring on red hides
  which change broke what.
- The request is a clean-up, not a behaviour change. If it mixes both, do the refactoring
  first and say the behaviour change comes after, as its own step.

## Procedure
1. **Name the smells** you see, each with a location: Long Function, Duplicated Code, Large
   Class, Long Parameter List, Feature Envy, Data Clumps, Primitive Obsession, Switch on
   type, Shotgun Surgery, Divergent Change, Speculative Generality, Dead Code.
2. **Pick a named refactoring for each:** Extract Function, Inline Function, Extract
   Variable, Rename, Move Function, Introduce Parameter Object, Replace Conditional with
   Polymorphism, Replace Primitive with Object, Split Phase, Remove Dead Code, and so on.
   Order them so each step leaves the code working.
3. **Do one step at a time.** Make the smallest change that completes one refactoring, run
   the tests, and record the result. If they fail, undo that step (don't fix forward) and
   either take a smaller step or stop and explain.
4. **Don't change behaviour.** No new features, fixed bugs, changed error messages or
   reformatting of untouched code inside a refactoring step. Note any bug you find and leave
   it for a separate change.
5. **Finish by running `./scripts/verify.sh`.**

## Output
Reply with:
- **Smells found:** each with its location.
- **Steps:** a numbered list: the refactoring's name, what moved where, and the test result
  after the step (pass, or the failure and that it was undone).
- **Verify:** the command and its last lines.
- **Left alone:** smells you didn't fix and bugs you noticed, with why.
