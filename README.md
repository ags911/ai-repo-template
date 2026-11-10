# AI-ready repository template

A small core that makes AI agent work verifiable, plus optional modules you add when a
real need shows up. Supports TypeScript and Python projects, separately or side by side.

## What is in the core
| File | Purpose |
| --- | --- |
| `AGENTS.md` | Rules for coding agents. Short on purpose. |
| `.verify.env` | Declares which stack profiles this repo uses. Nothing is auto-detected. |
| `scripts/verify.sh` | The single verification command, run identically locally and in CI. |
| `scripts/profiles/` | One script per stack. Missing tools or scripts fail; they never fall through. |
| `scripts/check-suppressions.sh` | Tripwire for added skips, suppressions, and deleted or renamed-away tests. |
| `scripts/ci-base-ref.sh` | Picks the diff base for that check in CI (PR base, the pre-push commit, or the empty tree on a first push). |
| `.github/workflows/verify.yml` | Runs `verify.sh` on every PR and push to main. |
| `.github/CODEOWNERS` | Requires human review for changes to rules, checks, and tool config. |
| `.github/dependabot.yml` | Weekly updates for the SHA-pinned Actions. |
| `SECURITY.md` | Where to report vulnerabilities. Fill in the placeholders. |
| `.github/pull_request_template.md` | What, why, linked issue, verify output, weakened checks, ADR. |
| `.github/ISSUE_TEMPLATE/` | Task and bug forms. A task issue is written so an agent can start from it alone. |

The enforcement is CI plus CODEOWNERS with branch protection. AGENTS.md tells agents the
rules; the pipeline is what holds when an agent ignores them. Branch protection and rulesets
need a public repo or a paid plan (Pro, Team, Enterprise). On a free private repo, CI still
runs on every PR, but nothing stops a merge while it is red or unreviewed.

## Setup
1. Copy the core into your repo.
2. Edit `.verify.env`: set `VERIFY_PROFILES` (`ts`, `python`, or `ts python`) and the project
   directories. For a monorepo with a Next.js app in `web/` and a Python agent in `agent/`:
   `VERIFY_PROFILES="ts python"`, `TS_DIR=web`, `PY_DIR=agent`.
3. Pin your toolchain: `.nvmrc` in the TS directory (CI reads it), `requires-python`
   in pyproject.toml, and commit lockfiles (`package-lock.json` / `pnpm-lock.yaml`, `uv.lock`).
4. **TypeScript:** define `lint`, `typecheck`, and `test` in package.json scripts
   (e.g. `eslint .`, `tsc --noEmit`, `vitest run`).
   **Python:** add `ruff`, `mypy`, and `pytest` as dev dependencies (`uv add --dev ruff mypy pytest`).
5. Replace `@your-handle` in CODEOWNERS, then in GitHub branch protection (or a ruleset) for
   `main` turn on "Require status checks" (select `verify`) and "Require review from Code
   Owners". Both need a public repo or a paid plan. In Settings > General, turn on
   "Automatically delete head branches": GitHub then retargets PRs that were based on a
   merged branch instead of closing them. Allow squash merging only, with the PR title and
   description as the commit message, so `main` gets one commit per PR carrying the
   template's fields. Fill in `SECURITY.md`.
6. The Actions in the workflows are pinned to commit SHAs. Dependabot (`.github/dependabot.yml`)
   opens a weekly PR when one has a new release. If you update one by hand, pin the new
   release's commit SHA and keep the version comment on the same line.
7. Delete `selftest/` and `.github/workflows/selftest.yml`: they test the template itself,
   and the workflow skips in repos created from it. Delete `modules/` once you have copied
   the modules you want.
8. Run `./scripts/verify.sh` locally until it passes.

## How agents use it
Agents run `./scripts/verify.sh` before claiming a task is done. AGENTS.md scales process to
the size of the change: a typo needs only verify, a feature needs tests, and a new
dependency or schema change needs a proposal before code.

Tool support for AGENTS.md varies and changes often. Check each tool's current docs rather
than adding per-tool rule files that drift out of sync.

**Monorepos.** Put rules that apply to one app in an `AGENTS.md` inside that app (for
example `web/AGENTS.md`). Open it with "Adds to the root AGENTS.md" and never restate root
rules, so the two can't disagree. In a test with Claude Code 2.1.306, a nested `AGENTS.md`
loaded both when a session started in `web/` and when a root session read a file in `web/`.

**Claude Code and why there is no `CLAUDE.md`.** Claude Code 2.1.277 and later reads
`AGENTS.md` directly, from the session's directory and every directory above it. It stops
reading `AGENTS.md` if a `CLAUDE.md` or `CLAUDE.local.md` exists in those directories. A
`CLAUDE.md` containing `@AGENTS.md` is a documented workaround, but in a test with Claude
Code 2.1.306 a headless session (`claude -p`) started in `src/` saw no repo rules through it.
Without a `CLAUDE.md`, sessions at the root and in `src/` both got them. So:
- don't add a project `CLAUDE.md` or `CLAUDE.local.md` (CODEOWNERS still covers `/CLAUDE.md`
  so adding one gets reviewed);
- on Claude Code older than 2.1.277, upgrade rather than adding `CLAUDE.md` back;
- your personal `~/.claude/CLAUDE.md` does not affect this.

## Day-to-day workflow
1. **One task per session.** Start a new session (or `/clear`) when you move to unrelated
   work, so old file reads and errors don't ride along on every turn. Give the agent the
   task, the files or area, and what done looks like.
2. **Size it with the table in AGENTS.md.** For a Significant change, use plan mode and get
   options and a recommendation before any code (the `tradeoff-analyzer` skill does this if
   you installed the skills module). Record the decision as an ADR if `docs/adr/` exists.
3. **Work on a branch from `main`.** Commit in small steps with messages that say what
   changed. The agent runs `./scripts/verify.sh` and shows its last lines before calling the
   task done. A "done" without that output isn't done.
4. **Read the diff.** Look hardest at tests, lint/type/CI config, and CODEOWNERS paths.
   AGENTS.md forbids loosening those without your approval, so any change there should match
   something you approved in the conversation.
5. **Open a PR and merge when CI and review pass.** The PR template asks for what and why,
   `Closes #N` (closes the issue on merge into the default branch), the verify output, any
   weakened checks with their approval, and the ADR. CI runs the same `verify.sh`, against
   `main` as it was when you pushed: if `main` has moved since, use "Update branch" and let
   CI run again before merging. With
   stacked PRs, let GitHub delete merged branches (setup step 5) so it retargets later PRs.
   Deleting a merged branch some other way (`git push --delete`, the API) can close PRs
   that were based on it instead.
6. **Before `/clear` or a new session, check the context is written down.** Anything only in
   the conversation is lost. What survives:

   | What | Where | Shared with others |
   | --- | --- | --- |
   | Decisions and why | ADRs in `docs/adr/` (adr module) | yes, committed |
   | What changed and why | commits and PR descriptions | yes |
   | Follow-ups | GitHub issues | yes |
   | Agreed rules | `.agent/learnings.md`, Accepted section | yes, committed |
   | Work in progress | `.agent/tasks/<id>.md` (agent-memory module) | no, gitignored |

   AGENTS.md tells agents to read these at the start of a task and to update the task file
   before stopping. Without the modules, ask for a short hand-off in the PR description.
7. **Work that spans sessions: open a draft PR early.** Keep the plan and progress in its
   description. Task files stay on your machine; a PR is visible from any machine, a cloud
   session, or another agent.
8. Start the next task in a new session.

### Keeping cost down
From Anthropic's [cost and intelligence guide](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence),
plus what applies to Claude Code:
- **Model and effort.** The guide recommends the newest Opus at default effort for most agent
  work, and comparing models by cost per finished task, not per token. Use lower effort
  for routine edits and re-run only the failures at higher effort; the guide measured that
  as about 40% cheaper than running everything at high, with the same pass rate.
- **Change model or effort between tasks, not mid-task.** The prompt cache depends on these
  settings, so a change makes the next turn pay full price for the whole conversation again.
- **Hand noisy work to a subagent** (large test runs, wide searches, long docs) so only its
  summary enters your conversation.
- **Keep always-loaded instructions short.** AGENTS.md loads every session; procedures belong
  in skills, which load only when used.
- **Turn off connectors and MCP servers** you don't use in this project.
- **Keep verify output small.** A passing run prints about 30 lines (TS sample) or 50
  (Python sample). If your suite grows to hundreds of tests, switch the test script to a
  compact reporter (`node --test --test-reporter=dot`, `vitest run --reporter=dot`; pytest's
  default is already compact). Failures still print in full.

## Optional modules
See `modules/README.md`: domain glossary, ADRs, PRDs, agent memory, an architecture
template with monolith and distributed profiles, real boundary checks
(dependency-cruiser for TS, import-linter for Python), and Claude Code skills for ADRs,
trade-off analysis, boundary-check generation, and quantum evaluation.

## Known limits
- `check-suppressions.sh` is pattern-based. It catches the common ways of weakening checks,
  not all of them. Code-owner review of test and config changes is the real backstop.
- Boundary tools check imports, not runtime calls (for example HTTP calls between modules).
- On the first push to `main` there is no earlier commit, so the suppression check diffs
  against the empty tree: every skip or suppression in the initial content needs a reason.
- Without branch protection (free private repos), CODEOWNERS and the `verify` check are
  advisory: GitHub shows them but doesn't block a merge.
- A force-push to `main` can leave the pre-push commit unfetchable; the suppression check then
  fails in CI rather than passing unchecked.

## Template self-test
`selftest/run.sh` builds throwaway repos from this template and asserts that `verify.sh` fails
(for the right reason) or passes in each case: empty profiles, missing tools and scripts, lint
failures that must stop the run, missing `REQUIRED_DIRS`, domain → infrastructure imports,
skips and suppressions with and without a reason, untracked files, deleted tests, the first
push to `main`, and a clean pass. `selftest/ts-sample/` and `selftest/py-sample/` are the
TypeScript and Python projects it uses, wired to `modules/boundaries-ts` and
`modules/boundaries-python`. CI runs it in `.github/workflows/selftest.yml`. Repos created from the
template can delete `selftest/` and that workflow.
