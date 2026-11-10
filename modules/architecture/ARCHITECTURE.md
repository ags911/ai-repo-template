# Architecture

Choose ONE profile below, delete the other, and fill in the modules.

---

## Profile A: Modular monolith
One deployable unit, split into modules with explicit public interfaces.
Choose when: one team, one database, modules not yet stable, or no need for independent scaling or deploys.

- Modules call each other in-process, only through each module's public interface.
- No module reads another module's tables directly.
- Events between modules are optional; use them for genuine fan-out, not by default.

## Profile B: Distributed services
Several independently deployable services.
Choose when: independent scaling, deploy cadence, or ownership is a demonstrated need.

- Services communicate asynchronously by default. Synchronous calls between services need an ADR.
- Each service owns its data; no shared database.
- Event payloads carry an id and a UTC timestamp.

---

## Modules
| Module | Responsibility | May depend on |
| --- | --- | --- |
| | | |

## Layer rules (both profiles)
- `domain`: business logic only. No imports from infrastructure, HTTP, or framework code.
- `application`: orchestrates use cases; depends on domain and on interfaces it defines.
- `infrastructure`: implements those interfaces (DB, external APIs).
- `presentation`: talks to application only, never directly to infrastructure.

Interfaces such as repositories are defined in domain/application and implemented in
infrastructure, so importing a repository *interface* from domain is allowed.
