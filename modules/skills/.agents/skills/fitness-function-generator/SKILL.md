---
name: fitness-function-generator
description: Turn the dependency rules in ARCHITECTURE.md into enforced boundary checks (dependency-cruiser rules for TypeScript, import-linter contracts for Python), set REQUIRED_DIRS, and prove each rule fails on a deliberate violation. Use when ARCHITECTURE.md's layer or module rules change, when installing the boundaries-ts or boundaries-python module, or when the user asks to enforce architecture rules in CI.
---

# Fitness function generator

Produces boundary-check config that `./scripts/verify.sh` runs, plus a proof table showing
every rule was seen to fail on a deliberate violation and pass once it was removed. A rule
that was never seen to fail does not count and must not be reported as enforced.

## Preconditions
- `ARCHITECTURE.md` exists and states dependency rules (the "Layer rules" section and/or
  the Modules table's "May depend on" column). If it has none, stop and ask the user for
  the rules. Do not infer them from the current imports, because that would enforce
  whatever is already there, mistakes included.
- `./scripts/verify.sh` passes before you start. If it fails, stop and report; you need a
  green baseline to know a later failure came from your probe.
- Read `.verify.env` for `VERIFY_PROFILES`, `TS_DIR`, and `PY_DIR`. Generate config for
  each profile listed there and nothing else.

## Approval first
Creating or editing `.dependency-cruiser.cjs`, `.importlinter`, `package.json` scripts, or
`.verify.env` changes verification config. Before touching them, show the user the rules
you will write (as a table: rule → source line in ARCHITECTURE.md) and the files you will
change, and wait for a yes. If `dependency-cruiser` or `import-linter` is not yet a dev
dependency, adding it is part of what they approve.

## Procedure
1. **Extract the rules.** Turn each sentence or table cell into a statement of the form
   "code in X must not import Y". Record the exact source line for each. Note exceptions
   the document allows. For example, ARCHITECTURE.md allows domain to import a repository
   *interface* defined in domain, so the rule targets the implementation directory.
2. **Map directories.** Find the real path of every layer or module the rules name
   (`src/domain`, `app/infrastructure`, ...). If a named layer has no directory, ask
   whether it is planned or the rule is stale. Do not write a rule for a path that does not exist.
3. **Write the config.**
   - **TypeScript** (in `TS_DIR`): start from `modules/boundaries-ts/.dependency-cruiser.cjs`
     if it is not installed yet. One `forbidden` rule per statement, `severity: "error"`,
     with a `name` that says the rule in words (`domain-not-infrastructure`). Paths are regexes
     relative to `TS_DIR`. For allow-lists from the Modules table, use `pathNot`. Keep
     `tsPreCompilationDeps: true` so type-only imports count. Keep the `no-circular`, `domain-not-reach-infrastructure`, `core-no-infra-packages` and
     `core-no-io-builtins` rules, adjusting their paths and `INFRA_PACKAGES` to the project.
     Install `modules/boundaries-ts/eslint.boundaries.js` too and set its `CORE` paths; it
     blocks `fetch`, `process` and other I/O globals that need no import.
     Make sure package.json has
     `"boundaries": "depcruise src --config .dependency-cruiser.cjs"`; the ts profile runs it.
   - **Python** (in `PY_DIR`): start from `modules/boundaries-python/.importlinter`. Set
     `root_package`. Use a `layers` contract for strict top-down layers, `forbidden` for
     single "must not import" rules, and `independence` for sibling modules that must not
     import each other. Keep the `core-no-infra-packages` and `core-no-io-modules` contracts
     and `include_external_packages = True`, adjusting the package list to the project
     (top-level names only). The python profile runs `lint-imports` when the file exists.
     Copy `modules/boundaries-python/test_core_io.py` into `tests/` and set its `CORE_DIRS`;
     it blocks subpackages, `os`/`pathlib`-style modules and bare `open()` calls.
4. **Set `REQUIRED_DIRS`** in `.verify.env` to every directory a rule names, as paths from
   the repo root (include the `TS_DIR`/`PY_DIR` prefix). Then a renamed or deleted layer
   fails verify instead of silently matching nothing.
5. **Run `./scripts/verify.sh`.** It must pass. If it fails on real existing code, the
   codebase already breaks the rule. Stop and report the violations; do not weaken the rule
   or add exceptions to get a pass.
6. **Prove every rule**, one at a time:
   1. Add a probe file inside the source layer that makes exactly that forbidden import,
      for example `src/domain/__fitness_probe.ts` importing from `src/infrastructure/...`.
      Make the probe otherwise clean: it uses what it imports (export it), it type-checks,
      and it passes the linter. Otherwise verify fails at lint or type-check before the
      boundary tool runs, and you have proved nothing. For `no-circular`, use two probe
      files that import each other.
   2. Run `./scripts/verify.sh`. It must exit non-zero, **and** the output must name this
      rule (the dependency-cruiser rule name or the import-linter contract name). A failure
      for any other reason does not count. Fix the probe and run it again.
   3. Delete the probe(s) and run `./scripts/verify.sh` again. It must pass.
   If a rule never fails, it is wrong (bad path regex, wrong package name, missing
   `tsConfig`). Fix the rule and prove it again. If you cannot make it fail, remove it and
   report it as **not enforced**.
7. **Clean up.** `git status` shows no probe files. The final `./scripts/verify.sh` passes.

## Output
- The files changed, and the rules added (name → source line in ARCHITECTURE.md).
- The `REQUIRED_DIRS` value set.
- The proof table:

| Rule | Probe | Failed with rule named | Passed after removal |
| --- | --- | --- | --- |
| domain-not-infrastructure | src/domain/__fitness_probe.ts → src/infrastructure/db.ts | yes | yes |

- **Not enforced**: any rule you could not prove, and why.
- The final verify command and its last lines.
