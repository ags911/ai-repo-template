---
name: quantum-evaluator
description: Map a system's deployables, data stores, and synchronous/asynchronous calls, count how many independently deployable units (architecture quanta) it really has, and recommend Profile A (modular monolith) or Profile B (distributed services) in ARCHITECTURE.md. Use when choosing an ARCHITECTURE.md profile, before splitting out or merging services, or when the user asks whether their services are really independent.
---

# Quantum evaluator

Produces an evidence-backed map of the system and a count of its **quanta**: groups of
deployables that can be released, scaled, and fail on their own. It reports
mismatches between the map and what `ARCHITECTURE.md` (or the team) claims. It does not edit
`ARCHITECTURE.md`.

## What makes two deployables one quantum
Put two deployables in the same quantum when any of these holds. Each one means neither
can be released or kept running on its own:
- they read or write the **same database** (same schema or same tables), even if they are
  called "services";
- one makes a **synchronous call** (HTTP, gRPC, direct DB read) to the other and cannot
  complete its own request if the other is down;
- they must be **deployed together**: a shared build artifact, a shared library version
  bumped in lockstep, a migration both depend on, or a deploy script that ships them as one.

Deployables that talk only **asynchronously** through a broker or queue, with a versioned
message contract, and that own their data, are separate quanta.

## Procedure
1. **Deployables.** Find everything that is built and run as its own process. Look in
   Dockerfiles, `docker-compose*.yml`, Kubernetes/Helm manifests, Terraform, serverless
   configs, Procfiles, `package.json`/`pyproject.toml` entry points, and the deploy jobs in
   `.github/workflows/`. For each, record its name, its path, and how it is deployed.
2. **Data stores.** For each database, cache, bucket, or search index, record who writes and
   who reads, with evidence: connection settings, env var names, ORM config, migration
   directories. If two deployables use different env vars that may point at the same
   database, mark it **unknown** and ask. Do not assume either way.
3. **Calls.** For each pair of deployables that communicate, record the direction, the
   mechanism (HTTP/gRPC client, queue or topic name, shared DB), and whether it is
   **sync** or **async**. A shared code library imported by both counts as a deploy-time
   coupling only if they must ship the same version together.
4. **Group into quanta** using the rules above. A chain of sync calls joins every member
   into one quantum.
5. **Compare with the claims.** Read `ARCHITECTURE.md` (which profile is chosen, the Modules
   table) and the README. Flag every mismatch, for example:
   - "services" that share one database: one quantum, not several;
   - Profile B chosen, but there is one quantum, or sync chains tie the services together;
   - Profile A chosen, but there are separately deployed units with their own data;
   - an async boundary with no versioned contract (consumers break when the producer changes).

## Output
```
## Deployables
| Name | Path / evidence | Deployed by |

## Data stores
| Store | Writers | Readers | Evidence |

## Calls
| From → To | Mechanism | Sync/async | Evidence |

## Quanta: <N>
1. <members> — joined by <shared DB / sync call / co-deploy>, evidence ...

## Recommendation
Profile A or B, and why, in terms of the quanta found and what the team needs to scale,
deploy, or own independently.

## Mismatches
<each mismatch, its evidence, and what fixing it would take>

## Unknowns
<anything marked unknown, and the question that would settle it>
```
If the recommendation changes the profile in `ARCHITECTURE.md`, say so and stop. The user
decides; if `docs/adr/` exists, offer to record the decision with adr-builder.
