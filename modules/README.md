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
| `skills` | You use Claude Code or Codex and want repeatable procedures for ADRs, trade-offs, boundary checks, quanta, schema migrations and refactoring |
| `complexity` | Files and functions keep growing and you want size and complexity limits enforced |
| `agent-hooks` | Agents sometimes say they're done without running verify, or you want verify before every push |
| `local-ci` | CI on a self-hosted runner on a laptop keeps failing when it sleeps or loses the network, or Actions minutes are running out |
| `ci-fallback` (planned, not built) | You run CI on a second cloud provider and want GitHub-hosted runners to take over when it runs out of free credits or goes down |

## glossary
Fill in real terms. Delete the example row.

## adr
Keep `docs/adr/README.md` as a one-line-per-decision index so agents read the index, not every ADR.

Turn on the `adr` verify profile (`VERIFY_PROFILES="ts adr"`; the module installs
`scripts/profiles/adr.sh`) to check, on every run, that each ADR is named `NNNN-title.md` with a
unique number, has a status of Proposed, Accepted or `Superseded by ADR-NNNN` (and that
successor exists), and is listed in the index. The `links` profile checks the index's links.
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
Six skills in the open `SKILL.md` format, shared by Claude Code and Codex:
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
| `schema-migration-review` | Release-by-release expand, migrate, contract steps for a schema, event or API change, each with a rollback and a check before the next | `adr` |
| `named-refactoring` | A clean-up done as named refactorings, one small step at a time, with the test result after each | (none) |

`/.agents/` and `/.claude/` are in CODEOWNERS, so changes to skills need code-owner review.

**Do they trigger?** `selftest/skill-triggers.sh` runs one fresh headless Claude Code session
per prompt (edits and shell disabled) and records which skill loaded: three prompts per skill
that should load it, and three unrelated prompts that should load none. It needs a signed-in
`claude` CLI and makes real model calls, so it is not part of CI. Rerun it after changing a
skill's `description`.
Last run (2026-11-11, Claude Code 2.1.306, default model): 19 of 19, including a single rename
that must load no skill. One run per prompt is
a small sample, and trigger rates can vary by model.

## agent-hooks
Turns "done means verified" from a rule an agent reads into one it can't skip, in Claude Code
and Codex, plus a git hook for everyone else.

- `scripts/agent-stop-check.sh`: the Stop hook both agents call when they try to finish a
  turn. It runs `./scripts/verify.sh` when there is uncommitted work, or commits beyond the
  base branch, unless the repo is exactly as it was the last time verify passed (it keeps
  that fingerprint in `.git/agent-stop-check.ok`). So committing a broken change before
  stopping doesn't get past it. If verify fails, it blocks the stop and hands the agent
  verify's last lines, telling it to fix the cause or, if that needs a human decision or
  would weaken a check, to stop and explain. If the agent was already sent back once
  (`stop_hook_active`), it lets it stop, so it can't loop.
- `.claude/settings.json`: registers the hook for Claude Code. If you already have this
  file, merge the `hooks.Stop` entry into it.
- `.codex/hooks.json`: registers it for Codex. Codex only runs repo hooks you have trusted:
  run `/hooks` in Codex once and approve it.
- `.githooks/pre-push`: runs verify before any push. Turn it on once per clone with
  `git config core.hooksPath .githooks`. `git push --no-verify` skips it; CI is still the gate.

Verify runs at the end of a turn only when the repo changed since its last pass, so it adds
verify's run time there and nowhere else.
The selftest checks each behaviour above; `selftest/agent-eval.sh stop_hook` checks it with
real agents.

## complexity
Size and complexity limits as fitness functions: verify fails when code grows past them. Set
the numbers for your project; the defaults are a starting point, not a standard.

- **TypeScript:** copy `eslint.complexity.js` next to your ESLint config and add `...complexity`
  to its array. It limits complexity (10), nesting depth (4), parameters (4), function length
  (60 lines) and file length (400 lines), in `src/`, not in tests.
- **Python:** paste `ruff-complexity.toml`'s tables into `pyproject.toml`. It turns on ruff's
  C901 (complexity 10), PLR0913 (4 arguments), PLR0912 (12 branches) and PLR0915 (50
  statements). It uses `extend-select`, so it adds to a rule selection you already have.
  Ruff has no file-length rule; statement count bounds function size instead.

The selftest proves each limit fails on a deliberate violation.

## local-ci
Runs your checks in Docker on your own machine, outside GitHub Actions, and can post the
result as a commit status. It resumes where it stopped after the laptop sleeps, the network
drops, or the run is killed.

**When it helps.** GitHub fails a self-hosted runner's job when the runner stops sending its
heartbeat ("The self-hosted runner lost communication with the server"). On a laptop, closing
the lid or a dropped network does that, and the job starts again from the beginning. Hosted
runners avoid it but use Actions minutes on private repos (see "Known limits" in the README).
This module has no runner to lose: the checks run in local containers, and GitHub only
receives the finished status.

**Install.**
1. Copy `scripts/local-ci/` into your repo. `/scripts/` is already in CODEOWNERS.
2. Edit `scripts/local-ci/lanes.conf`: one line per step (lane, step name, `-` or `net`,
   command). The example mirrors the `ts` and `python` verify profiles.
3. Edit `scripts/local-ci/Dockerfile` so the image has every tool your steps call.
4. Run `scripts/local-ci/selftest.sh` once. It proves the pause and kill-resume behaviour on
   your machine with its own small lanes, not yours (about three minutes).
5. Run `scripts/local-ci/run.sh`. Add `--post` to post the result as the `local-ci` commit
   status (needs `gh`, signed in, and the commit pushed). After the first post you can select
   `local-ci` under "Require status checks" in branch protection.

It needs bash, git and Docker. On macOS, Docker Desktop must share the repo's folder (it
shares `/Users` by default).

**How it works.**
- **Lanes.** Each lane runs in its own detached container with its own clone of the commit,
  kept in a Docker volume. Lanes run at the same time and don't share files. A lane keeps
  running if `run.sh` stops; running it again follows the lane to the end.
- **Checkpoints.** Each step that passes writes a marker under `.git/local-ci/<commit>/`, so a
  rerun skips it. A marker names the step and a hash of its command and the image, so editing
  either reruns it. A new clone (a new commit, a new image, or a deleted volume) clears the
  lane's markers, since what earlier steps installed went with the old clone. `--fresh`
  starts over.
- **Sleep.** Each lane checks the clock every 5 seconds. A step that fails after the clock
  jumped by more than 60 seconds (the laptop slept, or `docker pause`) reruns once.
- **Network.** Steps flagged `net` are retried, with a growing wait (3 attempts by default),
  and so is the image build. `--post` retries the status until GitHub accepts it; a 4xx
  answer other than 429 stops it.
- **Housekeeping.** The image tag is a hash of the Dockerfile and the optional `image/` build
  folder; older tags are pruned. Without `--post`, nothing leaves your machine.

The `run.sh` header lists the settings (`LOCAL_CI_GAP`, `LOCAL_CI_NET_TRIES` and others).

**Limits.**
- It tests the commit at HEAD, not uncommitted changes.
- A commit status is self-reported: anyone with write access can post `local-ci=success`.
  That suits a solo developer or a small trusted team. Keep the hosted `verify` workflow where
  you need CI you don't have to trust, such as pull requests from outside contributors.
- Only the lane's volume (`/work`) outlives a container, so the Dockerfile keeps tool caches
  and uv's Python there. If a step installs something elsewhere, a resumed lane won't have it.
- Steps must be safe to run twice: an interrupted or failed step reruns from the start.
- Each lane clones your local repository, so its branches appear as `origin/<branch>` there.
- The repo path must not contain `:` (Docker's `-v` syntax). Lane volumes stay until you
  remove them: `docker volume ls --filter name=local-ci-`.

### Parallel execution and evidence boundaries

Use `scripts/local-ci/run.sh --jobs 1` for serial execution, or `--jobs N` to bound
concurrent lane containers (default 2). This includes containers rejoined from an
interrupted run. Each lane has separate source and installed state. Steps in a lane
execute in declaration order; setup/build steps must precede checks that need them.

The example `lanes.conf` invokes authoritative `scripts/profiles/ts.sh` and
`scripts/profiles/python.sh`. Its repository lane calls `repository.sh`, which runs
configured extra profiles and suppression checks once. Copy that helper with the
other module files. Remove unused stack lanes and adjust installation directories
for your project. A committed `.verify.env` with a configured stack profile omitted
from the plan is rejected, as is omission of the repository checks. This check
requires the example's exact profile invocation commands; custom wrappers must keep
the profile calls explicit in the plan.

An explicit `--lane` selection is diagnostic, even if it names every lane. With
`--post`, its context is `<LOCAL_CI_CONTEXT>-partial`; it cannot publish the full
required status. Full runs still require every declared lane to pass. No live
GitHub calls occur without `--post`.

Set `LOCAL_CI_BASE_REF` to the verification base (default exported `BASE_REF`, then
`origin/main`). It must resolve locally. Containers receive its resolved commit,
so a moving base invalidates previous evidence. The host exports a bare repository
with only snapshot/base refs and Git objects: host Git config, hooks and credential
stores are not mounted. The original source repository is read, not modified.

Image identity includes the runner scripts. Step markers include the preceding
steps' identities and base commit, so changed prerequisites invalidate later
steps. Deleting a lane volume invalidates its installed-state checkpoints, even
when every step previously passed. New commits never reuse passing test results;
only download caches may be reused. Local state and posted statuses remain trusted
self-reports, not protection against a malicious developer.

Compare cold setup, warm complete verification and same-commit resume on the same
machine before choosing a concurrency limit. More containers can be slower or run
out of memory. Lane completion counts do not estimate remaining time.

The example assumes the stack profiles and repository extras are independent.
For coupled profiles whose order matters, put `bash scripts/verify.sh` in one lane
instead. The plan validator accepts that complete authoritative command; it
retains the verifier's ordering rather than attempting to infer dependencies.

## ci-fallback (planned, not built)
A design, not code yet. It will be built once a project has run CI on a second provider long
enough to measure how long a run takes and what it costs, because the module's deadlines and
budget come from those measurements. Until then, switching provider is a manual change.

**The problem.** A project that runs CI on another provider's free allowance (CircleCI, for
example) before falling back to GitHub-hosted runners has to notice, by hand, when the
allowance is used up or the provider is down, and switch. Pull requests wait in the meantime.

**What it will do.** Move validation from the primary provider to GitHub-hosted runners by
itself, for one commit at a time, when the primary gives no result in time. It is opt-in.

- **One direction only.** Primary provider to GitHub-hosted runners. Never back again by
  itself, and never to `local-ci` or a self-hosted runner: running CI on your own machine
  stays your decision.
- **Off by default.** A committed policy file holds `enabled: false`, the provider order, two
  deadlines and the one-switch limit. Turning it on is a reviewed pull request. A repository
  variable may switch it off at once, never on.
- **A spending stop first.** Turn it on only after setting a GitHub budget that stops usage
  when reached. GitHub's free minutes are shared by every private repository on the account,
  so an estimate cannot keep fallback runs free. A new budget does not count usage from
  earlier in the same billing cycle.
- **The trigger is a watchdog on GitHub.** On each pull request event, a small workflow waits
  for the primary's result on the exact head commit. It falls back when no run started
  within the start deadline (credits used up, a lost trigger, a stuck queue or an outage all
  look the same, and it does not need to know which), or when a run started but finished
  nothing within the completion deadline. A run that reported failing checks is a result:
  it **never** causes fallback, even past the completion deadline.
- **Signals it will not switch on.** Usage reports and status pages can warn, but they are
  delayed or describe the platform rather than your project, and providers do not
  necessarily document a call that returns your remaining credit. So they never switch
  provider by themselves.
- **One decision per commit.** The watchdog records what it decided (provider and reason)
  on the commit, once. At most one switch per commit; a new push starts with the primary
  again. Decisions for one commit are serialised, so two events cannot both switch. GitHub's
  check runs can be updated and a status shows only its latest value, so the module decides
  which record is authoritative and rejects a conflicting one.
- **Only the chosen provider's result counts.** The required check passes only for the
  provider the decision names, on that exact commit. A check of the same name from the
  replaced provider, or from an older commit, does not count. Where branch protection is
  available, pin the check's expected source.
- **No double runs.** Before the GitHub run starts, the watchdog cancels the primary's run
  for that commit. If it cannot confirm the cancellation, it stops and asks, unless the
  policy allows a possible double run.
- **The same checks and secrets.** The fallback runs the same `scripts/verify.sh` profiles
  as the primary, on GitHub-hosted runners, and keeps any private credential to the job that
  needs it. The watchdog's own token never reaches pull-request code.
- **When GitHub is unusable too,** the watchdog fails with a message suggesting `local-ci`
  (with `--post`). It never starts it.

**Settings it will have.** `enabled`, the provider order, the start and completion deadlines
(set from your measured run times, queue time included), the one-switch limit, whether a
possible double run is allowed (default no), and the off switch.

**Tests it will need.** No run started; a run that hangs; a failing run that must not fall
back; two pushes racing; a cancelled primary that keeps running; a check of the right name
from the wrong provider; and the token's absence from pull-request jobs.

**Without a second provider** do not install it: the core `verify` workflow is already the
GitHub path. Without GitHub minutes, it cannot help; use `local-ci`.

