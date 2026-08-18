# API reference
## JKDM SMK · IRIS POC

Three tiers of endpoint, and the distinction matters more than the payloads:

| Tier | Base | Who is meant to call it |
|---|---|---|
| **Public contract** | `http://localhost:52774/jkdm` | Consumers — agent systems, the portal, other JKDM systems. Also the ingestion flow. |
| **Control plane** | `http://localhost:52774/jkdm/routes` | Operators. Changes which implementation serves a contract. |
| **Backend** | `:8081` COBOL, `:8082` PHP | **IRIS only.** Never a consumer. Documented so you can see what the fabric absorbs. |

Port `52774` is the default in `.env.example`; the stock `52773` is avoided because developer machines often already have an IRIS on it.

**Authentication:** none. The POC exposes IRIS directly. In the target architecture InterSystems API Manager owns authn/authz at the L2 boundary (§4.2), and this contract sits behind it.

All `/jkdm` responses are `application/json; charset=utf-8`.

---

# 1 · Public contract

The only endpoints a consumer should know about. Their defining property: **the response shape does not change when the backend changes.**

## `GET /jkdm/health`

Liveness of the fabric itself. Says nothing about the backends — deliberately, so a load balancer does not remove IRIS because COBOL is down.

```json
{"status":"UP","fabric":"IRIS"}
```

**Use:** container healthcheck, load-balancer probe.

---

## `POST /jkdm/duty/calculate`

Compute duty, SST and total payable for a declaration the core already holds. **Read-only — persists nothing.**

**Request**
```json
{"declarationRef": "K1-2026-000101"}
```

**Response `200`**
```json
{
  "status": "OK",
  "declarationRef": "K1-2026-000101",
  "lineCount": 2,
  "totalCustomsValue": 30000,
  "totalDutyAmount": 1750,
  "totalSstAmount": 3175,
  "totalPayable": 4925,
  "preferenceApplied": 0,
  "calculatedAt": "2026-08-18T09:28:27+08:00",
  "lines": [ { "lineNo": 1, "hsCode": "8471.30.10", "hsDescription": "...",
               "rateApplied": 0.05, "customsValue": 20000,
               "lineDuty": 1000, "lineSst": 2100 } ],
  "backend": "COBOL"
}
```

| Status | Meaning | What the caller should do |
|---|---|---|
| `200` | Calculated | — |
| `400` | `declarationRef` missing | Fix the request |
| `404` | The core holds no such declaration | Fix the reference; do not retry |
| `502` | Backend unavailable | Retry later |

⚠ `404` and `502` are separated on purpose. Collapsing them tells a caller to retry something that will never succeed, and hides a real outage inside a stream of data errors.

**Routing:** `duty.calculate` is declared **fiscal** and is permanently `LEGACY` — always COBOL. See §2.

**Intended use:** interactive duty enquiry, and the lodgement call the EDIFACT ingestion flow makes internally.

---

## `GET /jkdm/manifest/{ref}`

Vessel manifest with its consignments. Read-only.

**Response `200`**
```json
{
  "status": "OK",
  "manifestRef": "MANIFEST-2026-0041",
  "vesselId": "9V-8841",
  "vesselName": "MV BINTANG SATU               ",
  "voyageNumber": "VOY-8841",
  "carrierTin": "C99000000001",
  "portOfDischarge": "MYPKG",
  "eta": "2026-08-20T06:00:00+08:00",
  "statusCode": "RL",
  "consignmentCount": 3,
  "totalGrossKg": 24000,
  "consignments": [ { "lineNo": 1, "consignmentRef": "CN-88410001",
                      "containerCount": 120, "grossKg": 12000,
                      "description": "..." } ],
  "backend": "COBOL"
}
```

| Status | Meaning |
|---|---|
| `200` | Found |
| `400` | Reference missing |
| `404` | No such manifest |
| `502` | Backend unavailable |

⚠ **The response differs by backend, and that is the point.** COBOL returns `vesselName` space-padded to 30 characters, `statusCode` as the stored `RL`, and `consignmentCount` counted from the records. PHP returns a trimmed name, `RELEASED` expanded from a lookup, and a count read from a denormalised column that has drifted. Whether any of that fails the §5.7 gate is the workshop exercise.

**Routing:** `manifest.lookup` is **non-fiscal** — all three modes are available.

---

## Response headers on both operations

```
X-SMK-Route-Mode: LEGACY | SHADOW | LIVE_NEW
X-SMK-Backend:    COBOL  | PHP
```

A **teaching device**. A routing decision is invisible by design, and these make it visible on a projector. **Strip them for production** — they leak internal topology to consumers.

---

# 2 · Control plane

## `GET /jkdm/console`

A clickable routing console, served by IRIS itself — one card per operation, three buttons each, live comparison evidence underneath. Returns `text/html`.

Fiscal operations render with a `FISCAL · LOCKED` badge and their non-LEGACY buttons disabled. Every button is a `PUT` to the endpoint below; the page adds no capability the API does not already expose.

**Use:** operating the transition without a terminal. This is the control surface a duty officer or release manager would actually touch.

---

## `GET /jkdm/routes`

The routing table, which is a **policy artefact, not just configuration**.

```json
[
  { "operation": "duty.calculate",  "mode": "LEGACY", "authoritative": "COBOL",
    "fiscal": 1, "modesAvailable": "LEGACY (locked - fiscal)" },
  { "operation": "manifest.lookup", "mode": "LEGACY", "authoritative": "COBOL",
    "fiscal": 0, "modesAvailable": "LEGACY, SHADOW, LIVE_NEW" }
]
```

**Use:** see which implementation is authoritative for each operation, and which operations are permitted to move at all.

---

## `PUT /jkdm/routes/{operation}/{mode}`

Change which implementation serves an operation. **This single call is the entire cutover mechanism**, and the rollback is the same call with the previous mode.

| Mode | Who is called | Consumer receives |
|---|---|---|
| `LEGACY` | COBOL only | COBOL |
| `SHADOW` | COBOL **and** PHP | **COBOL.** PHP's answer is discarded, both are compared asynchronously. |
| `LIVE_NEW` | PHP only | PHP |

**Three outcomes, three status codes:**

```
200  {"operation":"manifest.lookup","mode":"SHADOW"}

400  {"error":"mode must be one of LEGACY, SHADOW, LIVE_NEW","received":"BANANA"}

409  {"error":"duty.calculate is a fiscal operation and is locked to LEGACY",
      "policy":"fiscal","reference":"SMK 5.8"}
```

⚠ The `409` is the interesting one. An operation that computes money cannot be moved — §5.8's *"leave the revenue core in COBOL"* enforced by the router rather than remembered by a person. It also removes the double-write hazard for the operations that matter: shadowing a lodgement or a revenue posting would write twice, and those are exactly the operations this refuses.

**Known limit:** `fiscal` is a proxy for "has side effects", and the two are not identical. A non-fiscal operation that writes would still double-write under `SHADOW`. Nothing checks that today.

---

## `GET /jkdm/comparisons`

Equivalence evidence — the artefact that takes a module through the §5.7 gate and populates its Migration Passport (§5.6).

```json
{
  "equivalenceRate": { "manifest.lookup": "50.00% (1/2)" },
  "recent": [ { "id": "2", "operation": "manifest.lookup",
                "reference": "MANIFEST-2026-0044",
                "verdict": "MATERIAL_DIFF",
                "comparedAt": "2026-08-18 09:26:13" } ]
}
```

Verdicts are `EQUIVALENT`, `MATERIAL_DIFF` or `FISCAL_DIFF`.

An operation only appears here once it has been shadowed. A fiscal operation never will, and that is correct rather than a gap.

⚠ Read the breakdown, not the headline. `EQUIVALENT` requires *every* field to match, and one padded vessel name spoils it. The number that gates a wave is the FISCAL count.

---

# 3 · Backend endpoints

**Not a public API.** Documented because the difference between them is the clearest answer to "what is the fabric actually doing".

## COBOL core · `:8081`

| Endpoint | Notes |
|---|---|
| `GET /health` | Checks the binaries and the flat files exist |
| `POST /duty/calculate` | Body `{"declarationRef":"..."}` |
| `GET /manifest/{ref}` | |

Returns **fixed-width records** in a JSON envelope:

```json
{"backend":"COBOL",
 "raw":"OKK1-2026-000104      007000001722263000000108847...",
 "lines":["LN0018471.30.10Portable automatic data processing 000050000000001234550000000006173..."]}
```

Positional, zero-padded, implied decimals, `PIC X(35)` truncated text, `YYYYMMDDHHMMSS` with no timezone. `JKDM.Util.CobolParser` normalises it into the canonical shape — `TOT-DUTY` lives at characters 39–51.

⚠ **Invocation is a POC shortcut.** A Flask wrapper shells out to the compiled binary per request. That is one of four unresolved options for how IRIS invokes Visual COBOL in production (§5.3), chosen for convenience, **not** a recommendation.

## PHP / Laravel · `:8082`

| Endpoint | Notes |
|---|---|
| `GET /health` | |
| `POST /duty/calculate` | Same request shape |
| `GET /manifest/{ref}` | |

Returns ordinary JSON from Eloquent. No normalisation needed — which is exactly why the COBOL side proves the point.

⚠ Uses **native PHP floats** deliberately. `1088.46` against COBOL's `1088.47`. Do not fix it; §5.7 prohibits floats for money in a warning box, and the demo exists to show the prohibition being violated by code that looks correct.

---

# Quick reference

```bash
IRIS=http://localhost:52774/jkdm

curl -s $IRIS/health
curl -s $IRIS/routes | python3 -m json.tool
curl -s $IRIS/comparisons | python3 -m json.tool

curl -s -X POST -H 'Content-Type: application/json' \
     -d '{"declarationRef":"K1-2026-000104"}' $IRIS/duty/calculate

curl -s $IRIS/manifest/MANIFEST-2026-0044

curl -s -X PUT $IRIS/routes/manifest.lookup/SHADOW    # 200
curl -s -X PUT $IRIS/routes/duty.calculate/SHADOW     # 409, fiscal

curl -s -D- -o /dev/null $IRIS/manifest/MANIFEST-2026-0041 | grep -i x-smk
```
