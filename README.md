# JKDM SMK · IRIS POC

Two flows from the SMK Enterprise & Technical Architecture (Vol. I, v6.1), built and running:

- **Flow A — EDIFACT/SFTP ingestion.** IRIS pulls CUSDEC files from the DFTZ partner drop, audits before parsing, transforms to a canonical customs message, lodges through the public contract, acknowledges back to the partner. <span>(§2.7, §4.3.5)</span>
- **Flow B — strangler routing.** One API contract; IRIS routes to COBOL or PHP, shadows and compares during transition. <span>(Figure 4.3.1, Figure 5.9.1 steps 6–8)</span>

**Repository:** <https://github.com/martyn0022/jkdm-iris-poc>

```bash
git clone https://github.com/martyn0022/jkdm-iris-poc.git
cd jkdm-iris-poc
cp .env.example .env
docker compose up -d --build
./scripts/preflight.sh
```

First build takes 8–12 minutes. Subsequent starts are seconds.

---

## Status: running and verified

Both flows have been run end to end against IRIS 2026.1 Community. Verified: SFTP pull, audit-before-parse, EDIFACT parse and canonical transform, lodgement via the strangler router, CONTRL/APERAK acknowledgements, all three routing modes, and the comparator producing FISCAL/MATERIAL/IGNORE evidence.

`./scripts/preflight.sh` runs 14 checks and tells you whether the session can go ahead. Run it before the room fills up.

**Two environment notes:**

- Uses the official `containers.intersystems.com/intersystems/iris-community` image. The `intersystemsdc/iris-community` image runs an `iris-after-start` hook that fails on current builds and takes the container down with it.
- **IRIS does not use the stock 52773/1972.** A developer machine very often already has an IRIS holding those, and the failure mode is ugly — every other container comes up healthy and only IRIS dies with `port is already allocated`. Defaults here are **52774/1973**, set in `.env.example`. Every script reads `.env`; the Management Portal URLs written in `docs/` do not, so update those by hand if you move IRIS again.
- **Any hardware.** Every image is multi-arch, including the SFTP server, which is built from `alpine` + OpenSSH rather than pulled. No Rosetta, no platform pins.

---

## Services

| Service | Port | Role |
|---|---|---|
| `iris` | 52774 | The fabric. REST at `/jkdm`, portal at `/csp/sys/UtilHome.csp` |
| `cobol-core` | 8081 | GnuCOBOL duty calculation + HTTP wrapper |
| `php-service` | 8082 | Laravel 10 + Eloquent over Postgres |
| `postgres` | 5432 | Shared source of truth |
| `sftp` | 2222 | DFTZ partner drop (`dftz` / `dftz_poc`) |
| `generator` | — | Runs once: Postgres → COBOL flat file, then exits |

---

## Running the demos

```bash
./scripts/preflight.sh                  # 14 checks before you start
./scripts/reset.sh                      # clean slate

./scripts/drop-edi.sh                   # Flow A: partner uploads a declaration
./scripts/drop-edi.sh all|bad|manifest
./scripts/audit.sh                      # the ingestion evidence trail

./scripts/demo.sh                       # Flow B: fiscal lock, then three modes
# or drive it from the browser:  http://localhost:52774/jkdm/console
./scripts/audit.sh diffs                # every field difference, classified
./scripts/php-fail.sh on                # break PHP; shadow consumers must not notice
```

`X-SMK-Backend` and `X-SMK-Route-Mode` response headers reveal the routing decision. A teaching device — strip for production.

### The routing table is a policy

Each operation is declared fiscal or not, and the router enforces it:

| Operation | Fiscal | Modes available |
|---|---|---|
| `duty.calculate` | yes | `LEGACY` only — the router returns **409** on any attempt to move it |
| `manifest.lookup` | no | `LEGACY`, `SHADOW`, `LIVE_NEW` |

That is SMK §5.8 — *"leave the revenue core in COBOL"* — expressed as configuration rather than convention. It also closes the shadow-on-writes problem for the cases that matter: the operations you must never run twice are the fiscal ones, and those are exactly the ones that cannot be shadowed.

⚠ **A limit of the technique, not a defect in this build.** `Fiscal` is a proxy for "has side effects", and the two are not the same thing. A non-fiscal operation that *wrote* would be double-written under `SHADOW`, because the router calls the second backend unconditionally and cannot tell a read from a write.

Nothing in this POC writes — every operation on both backends reads and computes — so it cannot happen here and cannot be demonstrated. That is deliberate: a write-free operation was chosen precisely so shadow mode would be safe to show. The gap is real for production, where both backends share one database.

### Test declarations

| Ref | Expected |
|---|---|
| `K1-2026-000101/2/3` | Agree on all fiscal fields. |
| **`K1-2026-000104`** | **FISCAL_DIFF.** COBOL `1088.47`, PHP `1088.46`. |
| **`K1-2026-000105`** | **FISCAL_DIFF.** FTA threshold boundary, ~RM 600. |
| `K1-2026-000106` | Agrees. FTA clearly above threshold. |

⚠ No declaration comes back `EQUIVALENT` on a first run — COBOL truncates descriptions at `PIC X(35)`, so every one carries a MATERIAL difference. That is deliberate. The number that gates a wave is the FISCAL count, and separating the two is the workshop's central exercise.

### EDIFACT samples

| File | Outcome |
|---|---|
| `CUSDEC_K1-2026-0001xx.edi` | `LODGED` — six declarations matching the seed data |
| `CUSDEC_MALFORMED.edi` | `SYNTAX` reject — truncated interchange, no UNZ trailer |
| `CUSDEC_UNPRICEABLE.edi` | `BUSINESS` reject — parses, but the core holds no such declaration |
| `CUSCAR_MANIFEST.edi` | `UNSUPPORTED` reject — **this is the guided lab**; describes `MANIFEST-2026-0041`, which the database holds |

Regenerate from Postgres with `python3 edi/generate_samples.py`.

---

## The two fiscal differences

**#1 — line-level vs total-level rounding (`K1-2026-000104`)**

COBOL rounds each line to 2dp in `COMP-3` packed decimal, then accumulates. PHP sums at full float precision and rounds once. Seven lines, delta exactly `0.01`.

Nothing is hardcoded to force this. It is the genuine behaviour of the two implementations. Being able to say *"we did not plant this"* is the point.

**#2 — FTA threshold boundary (`K1-2026-000105`)**

COBOL applies preference at `>=`; PHP at `>`. A declaration sitting exactly on 40.00% gets different treatment. Hand-coded, but a realistic conversion defect.

### Do not "fix" the PHP before the session

`DutyController` uses native floats on purpose. If someone says *"you should have used bcmath"* — that is the correct conclusion, and exactly what the §5.7 gate exists to surface **before** cutover. `preflight.sh` fails if the difference disappears.

---

## Expect noise first

Attendees will see `IGNORE` and `MATERIAL` differences — timestamps, truncated descriptions, backend names — and conclude the comparator is broken. Let it happen. That *is* the lesson for why the three-way classification exists.

Then let them find `K1-2026-000104` themselves. Do not point at it.

---

## Why the flat file and the EDI samples are both generated

Both backends must read the **same** data, or a difference could be data divergence rather than logic.

```
Postgres ──> Laravel (Eloquent, direct)
    ├──────> generator/generate_flatfile.py ──> declline.dat ──> COBOL (copybook)
    └──────> edi/generate_samples.py        ──> CUSDEC *.edi  ──> partner drop
```

`generate_flatfile.py` **is** the copybook-to-schema mapping as executable code — the CardDemo TS2-04 / TS3-04 decision made visible. Open it during the demo; more convincing than a slide about it.

---

## Known limitations — state these, don't design around them

- **No D96A schemas.** IRIS parses EDIFACT structurally but does not ship the UN/EDIFACT message dictionary; those are licensed SEF files. So the intake validates the *envelope*, not full standards conformance, and `CusdecToCanonical` addresses fields by position rather than by name. With the SEF loaded it becomes a graphical DTL. Real line item, small cost, must land before partner conformance testing.
- **X.400.** §2.7 records the ECS/EDI DFTZ link as X.400 · SFTP. IRIS speaks SFTP and EDIFACT natively; it does not speak X.400. Needs a gateway or a partner-side change.
- **Lodgement is a pricing call.** `CoreDeclarationOp` asks the core to price a declaration it already holds. A declaration that arrives by file and is unknown to the core is rejected — correct behaviour, but it means Flow A does not itself create declarations.
- **How IRIS invokes COBOL.** The HTTP-wrapper-shelling-out approach is one of four unresolved options (spec §5.3), chosen for POC convenience. Not a recommendation.
- **No API Manager.** The target architecture puts authn/authz in InterSystems API Manager (§4.2, L2). This POC exposes IRIS directly and unauthenticated.

**Not in scope:** data migration (SMK §5.5 — a separate 12-step pipeline; IRIS appears nowhere in it), MQ replacement, AI gateway.

---

## Layout

```
├── docs/
│   ├── INSTRUCTOR-SCRIPT.md   run the session from this
│   ├── EXERCISE.md            guided lab - 10 steps, answers included
│   ├── API.md                 endpoint reference, all three tiers
│   ├── PROTOTYPE.md           the enablement segment: IRIS beyond an ESB
│   ├── session-deck.html      THE DECK - 29 slides, session order, demo hand-offs
│   └── architecture.html      both flows: as shipped, and after the exercise
├── postgres/init/             schema + seed with engineered differences
├── generator/                 Postgres -> fixed-width flat file
├── edi/
│   ├── generate_samples.py    Postgres -> CUSDEC EDIFACT
│   └── samples/               9 sample messages
├── cobol/
│   ├── copybook/DECLLINE.cpy  PIC X(35) truncation lives here
│   ├── src/DUTYCALC.cbl       COMP-3 arithmetic, ROUNDED per line
│   └── wrapper/app.py         HTTP shim - one of four options in §5.3
├── laravel/                   Laravel 10, Eloquent, native float arithmetic
├── sftp/                      partner drop (inbound) and acks (outbound)
├── iris/
│   ├── iris.script            build-time namespace + compile + seed
│   └── src/JKDM/
│       ├── Production.cls             Flow A interoperability production
│       ├── BS/EdiInboundService.cls   the SFTP pull
│       ├── BS/StranglerRouter.cls     the router (Figure 4.3.1)
│       ├── BP/DeclarationIntake.cls   audit BEFORE parse
│       ├── BP/Comparator.cls          field-level equivalence
│       ├── BO/                        audit, core lodgement, ack
│       ├── Xform/CusdecToCanonical    the retired EDIFACT translator
│       ├── Config/RouteMode.cls       the routing table
│       ├── Rule/DutyEquivalence.cls   FISCAL list, verbatim from §5.7
│       ├── Util/EdifactNav.cls        segment navigation
│       ├── Util/CobolParser.cls       fixed-width -> canonical
│       └── Util/Report.cls            the terminal reports
└── scripts/                   preflight, reset, demo, drop-edi, audit, php-fail
```

Session plan and delivery notes: `docs/INSTRUCTOR-SCRIPT.md`.
Build spec: `../IRIS POC Build Spec and Workshop Guide.md`.
