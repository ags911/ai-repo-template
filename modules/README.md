# Optional modules

Add a module when you have a problem it solves, not before. To install one, copy its
contents into the repo root (paths inside each module mirror their destination), then
do whatever its section below says.

| Module | Add it when |
| --- | --- |
| `glossary` | Agents (or people) keep using different names for the same domain concept |
| `adr` | Decisions are being re-argued, or nobody remembers why something is the way it is |
| `prd` | Features span several sessions or need sign-off against acceptance criteria |
| `agent-memory` | Agents repeatedly hit the same environment traps across sessions |
| `architecture` | The codebase has distinct modules whose dependencies you want to fix |
| `boundaries-ts` / `boundaries-python` | You have an ARCHITECTURE.md and want its rules enforced in CI |
| `skills` | You use Claude Code or Codex and want repeatable procedures for ADRs, trade-offs, boundary checks, and quanta |
| `agent-hooks` | Agents sometimes say they're done without running verify, or you want verify before every push |

## glossary
Fill in real terms. Delete the example row.

## adr
Keep `docs/adr/README.md` as a one-line-per-decision index so agents read the index, not every ADR.

## agent-memory
`.agent/tasks/` is already gitignored by the core. `.agent/learnings.md` is already in CODEOWNERS.

## architecture
Pick one profile from `ARCHITECTURE.md`, delete the other, and record the choice as an ADR if you use that module.

## boundaries-ts
1. `npm i -D dependency-cruiser`
2. Copy `.dependency-cruiser.cjs` to the TS project root and adjust the paths.
3. Add `"boundaries": "depcruise src --config .dependency-cruiser.cjs"` to package.json scripts.
4. Set `REQUIRED_DIRS` in `.verify.env` to the layer directories, so a missing or renamed
   directory fails instead of passing with nothing checked.
5. The config file is CommonJS. If ESLint lints it, declare `sourceType: "commonjs"` for
   `*.cjs` files (see `selftest/ts-sample/eslint.config.js`).
6. Copy `eslint.boundaries.js` next to your ESLint config and add `...boundaries` to its
   array (see `selftest/ts-sample/eslint.config.js`). Rename it to `.mjs` if package.json
   isn't `"type": "module"`.

Besides the direct layer rules, the config ships three more:
- `domain-not-reach-infrastructure`: domain may not reach infrastructure indirectly either,
  for example through a barrel file in `src/shared` that re-exports it.
- `core-no-infra-packages`: domain and application may not import infrastructure packages
  (database drivers, ORMs, HTTP frameworks, cloud SDKs). Edit `INFRA_PACKAGES` for your project.
- `core-no-io-builtins`: domain and application may not use Node's network, file or process
  modules directly.

`eslint.boundaries.js` covers I/O that needs no import, which dependency-cruiser can't see.
In domain and application it blocks the globals `fetch`, `XMLHttpRequest`, `WebSocket`,
`EventSource`, `process`, `require`, `Bun` and `Deno`, including through `globalThis`.

Path aliases from tsconfig (`"@infra/*"`) are resolved, so they are checked like relative imports.

The rules apply to test files too: a test under `src/application` may not import
infrastructure. Use a fake that implements the domain interface instead.
`selftest/ts-sample` is a working example of this module.

## boundaries-python
1. Add `import-linter` to your dev dependencies.
2. Copy `.importlinter` to the Python project root and set `root_package`.
3. Set `REQUIRED_DIRS` in `.verify.env` as above. The profile runs `lint-imports` automatically when the file exists.
4. Copy `test_core_io.py` into your `tests/` directory and set `CORE_DIRS` to your domain and
   application directories. pytest runs it with the rest of your tests.

Besides the layer contracts, the config ships two that match the TypeScript rules:
- `core-no-infra-packages`: domain and application may not import infrastructure packages
  (database drivers, ORMs, web frameworks, HTTP clients, cloud SDKs). Edit the list for your
  project. import-linter accepts only top-level names, so `azure` is listed, not
  `azure.storage`, and Google Cloud can't be listed without blocking all of `google`.
- `core-no-io-modules`: domain and application may not import the standard library's
  network, process or file modules (`socket`, `http`, `subprocess`, `shutil` and others).

`test_core_io.py` covers what import-linter can't express. In `CORE_DIRS` it fails on:
- imports of subpackages such as `google.cloud` and `urllib.request` (`urllib.parse` stays
  allowed);
- imports of `os`, `pathlib`, `io`, `tempfile`, `glob`, `shelve`, `importlib` and `builtins`;
- bare calls to `open()` and `__import__()`, unless the file defines its own `open`
  (a method such as `account.open()` is fine).

It reads source code, so it can't see I/O hidden behind `getattr` or `eval`. Code review
is the backstop for those.

`selftest/py-sample` is a working example of this module.

## skills
Four skills in the open `SKILL.md` format, shared by Claude Code and Codex:
- `.agents/skills/` holds the skills. Codex reads this folder.
- `.claude/skills/` holds a relative symlink to each one. Claude Code 2.1.306 reads only this
  folder; in a test, a skill that existed only in `.agents/skills/` didn't load.

Copy the module with something that keeps symlinks (`cp -R`, or a git commit). On Windows,
enable symlinks in git (`git config core.symlinks true`, with Developer Mode on) before
cloning. Without that, the links become small text files and Claude Code sees no skills.
The `windows-symlinks` job in `.github/workflows/selftest.yml` checks both cases on a Windows
runner.
`selftest/run.sh` checks that every skill has its link and every link has a skill.

An agent loads a skill when the task matches its description; in Claude Code you can also
run one by name, for example `/adr-builder`.

| Skill | Produces | Works best with |
| --- | --- | --- |
| `tradeoff-analyzer` | Options, gains and costs against the project's priorities, reversibility, recommendation, ADR yes/no | `architecture`, `adr`, `prd` |
| `adr-builder` | A numbered ADR with status Proposed, plus its index row | `adr` (required) |
| `fitness-function-generator` | dependency-cruiser rules or import-linter contracts, `REQUIRED_DIRS`, and proof that each rule fails | `architecture` + `boundaries-ts` / `boundaries-python` (required) |
| `quantum-evaluator` | Deployables, data stores, calls, the number of quanta, a recommended profile, mismatches | `architecture` |

`/.agents/` and `/.claude/` are in CODEOWNERS, so changes to skills need code-owner review.

**Do they trigger?** `selftest/skill-triggers.sh` runs one fresh headless Claude Code session
per prompt (edits and shell disabled) and records which skill loaded: three prompts per skill
that should load it, and three unrelated prompts that should load none. It needs a signed-in
`claude` CLI and makes real model calls, so it is not part of CI. Rerun it after changing a
skill's `description`.
Last run (2026-11-10, Claude Code 2.1.306, default model): 15 of 15. One run per prompt is
a small sample, and trigger rates can vary by model.

## agent-hooks
Turns "done means verified" from a rule an agent reads into one it can't skip, in Claude Code
and Codex, plus a git hook for everyone else.

- `scripts/agent-stop-check.sh`: the Stop hook both agents call when they try to finish a
  turn. If no files changed, it does nothing. If files changed and `./scripts/verify.sh`
  fails, it blocks the stop and hands the agent verify's last lines, telling it to fix the
  cause or, if that needs a human decision or would weaken a check, to stop and explain.
  If the agent was already sent back once (`stop_hook_active`), it lets it stop, so it
  can't loop.
- `.claude/settings.json`: registers the hook for Claude Code. If you already have this
  file, merge the `hooks.Stop` entry into it.
- `.codex/hooks.json`: registers it for Codex. Codex only runs repo hooks you have trusted:
  run `/hooks` in Codex once and approve it.
- `.githooks/pre-push`: runs verify before any push. Turn it on once per clone with
  `git config core.hooksPath .githooks`. `git push --no-verify` skips it; CI is still the gate.

Verify runs at the end of any turn that changed files, so it adds verify's run time there.
The selftest checks each behaviour above; `selftest/agent-eval.sh stop_hook` checks it with
real agents.
