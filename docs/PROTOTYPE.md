# The prototype
## What the same system looks like if the application and data tiers move inward

**Namespace:** `PROTOTYPE` · **Contract:** `/prototype` · **Driver:** `./scripts/prototype.sh`

A separate namespace on the same instance, deliberately. It cannot reach the POC's data by accident, and the separation is what lets you call it a sketch without anyone taking that on trust.

---

## Read this before you show it

This segment shows IRIS doing what the tender assigns to **PHP/Laravel** (TS3-02) and **EDB Postgres** (TS2-03, TS3-03). Unijaya wrote that architecture and proposed it to JKDM.

Framed as a correction it lands badly — the platform vendor relitigating the SI's committed design, mid-tender. Framed correctly it is their own argument, exercised.

> §5.8: *"…the choice can be confirmed or substituted per module without breaking integrations, and performance-sensitive paths may be isolated behind the same boundary in an alternative approved runtime if assessment requires."*

That sentence is an invitation, written by them. This is what one of those alternatives looks like.

**The interop interface does not change.** Same EDIFACT parsing — the prototype calls `JKDM.Util.EdifactNav`, mapped from the POC namespace, so it is literally the same code. Same contract shapes. A consumer cannot tell the difference from outside, which is the only honest way to compare.

**Do not pitch. Demonstrate, then stop talking.**

---

## What it does

| | Tender stack | Prototype |
|---|---|---|
| Partner ingestion | IRIS | IRIS — *unchanged* |
| Canonical model | IRIS | IRIS — *unchanged* |
| API contract | IRIS + API Manager | IRIS — *unchanged* |
| Application logic | PHP / Laravel | IRIS (ObjectScript **or** Python) |
| Data | EDB Postgres | IRIS |
| Fiscal core | COBOL | **COBOL — unchanged** |

The last row matters. §5.8 says the revenue core stays in COBOL, and nothing here proposes otherwise. The prototype is a candidate for the *satellite* modules, which is exactly the quadrant the document marks convert-first.

---

## Four results, one declaration

```
COBOL core (authoritative)   1088.47
PHP - the tender stack       1088.46
IRIS - ObjectScript          1088.47
IRIS - Python                1088.47
```

⚠ **Say what this is and is not.** It is *not* "IRIS is more accurate than PHP". Both IRIS implementations round each line before accumulating **because the COBOL does**; the tender's PHP rounds once at the end. That is a decision, taken deliberately, to agree with the system that has been posting revenue for twenty years.

The point is narrower and better: *agreeing with the system of record is a choice you make, and it is easier to make when the person writing the new code can read the old behaviour and match it.* Any of the three could have been written either way.

---

## The limitation that disappears

The main POC carries a documented gap: **Flow A never creates a declaration.** It parses a partner file, canonicalises it, and asks the core to price a declaration the core must already hold.

That was not laziness. Writing meant crossing into Postgres, and a write in a shadowed path is precisely what shadow mode cannot do safely. So the POC chose a read-only operation and said so.

```
main POC  : 404 - declaration not found
prototype : LODGED - parsed, persisted and priced in one call
```

Same file, same parser. The prototype persists it because the storage is in the same process — one transaction, no tier boundary, no second datastore to keep consistent.

🗣 **The line to use:** "That limitation came from the tier boundary. Move the boundary and it is not there. I am not claiming that is free — I am claiming it is where the cost was."

---

## Lead with Python

The room is PHP-strong and ObjectScript-zero. The unspoken objection is staffing, and §5.8 chose PHP partly for the local hiring pool. If you do not raise it, someone is thinking it and not saying it.

`PT.Svc.DutyPy` is ordinary Python with ordinary SQL:

```python
for line_no, hs_code, customs_value in iris.sql.exec(
    "SELECT LineNo, HSCode, CustomsValue FROM PT_Data.DeclarationLine "
    "WHERE Declaration = ? ORDER BY LineNo", pRef):
    ...
    line_duty = money(value * rate)
```

Nothing there is IRIS-specific except `iris.sql.exec`. A PHP developer reads it without training.

⚠ **Be equally honest:** Python is not PHP. This narrows the hiring argument from *"a language nobody here knows"* to *"a language most teams already have"*. It does not remove it.

---

## Where this is genuinely weaker

Say these out loud. A one-sided demo gets discounted wholesale.

- **CRUD admin screens.** Laravel is faster to build and cheaper to staff. Most of the convert-first quadrant is exactly this.
- **The hiring pool.** Real, and §5.8 was right to weigh it.
- **The fiscal core.** Stays in COBOL regardless. IRIS-native is not a candidate there and claiming otherwise damages everything else.
- **Ecosystem.** Composer has more packages than IRIS does. That is not close.

---

## Running it

```bash
./scripts/prototype.sh                    # the whole segment, ~30 seconds
./scripts/prototype.sh K1-2026-000105     # the FTA boundary declaration
```

Individually:

```bash
P=http://localhost:52774/prototype

curl -s $P/health
curl -s -X POST -H 'Content-Type: application/json' \
     -d '{"declarationRef":"K1-2026-000104"}' $P/duty/calculate
curl -s -X POST -H 'Content-Type: application/json' \
     -d '{"declarationRef":"K1-2026-000104"}' $P/duty/python
curl -s $P/manifest/MANIFEST-2026-0041

# EDIFACT in, persisted and priced out - note the content type
curl -s -X POST -H 'Content-Type: text/plain' \
     --data-binary @edi/samples/CUSDEC_K1-2026-000101.edi $P/ingest

curl -s $P/sql          # objects and SQL over the same storage
curl -s $P/explain      # artefact and tier counts
```

Management Portal, `PROTOTYPE` namespace:
`http://localhost:52774/csp/sys/exp/%25CSP.UI.Portal.ClassList.zen?$NAMESPACE=PROTOTYPE`

---

## What is deliberately missing

Honesty about scope, so nobody thinks this is a product:

- **No interoperability production.** The namespace is interop-enabled and the parser is shared, but there is no second SFTP poller — two productions fighting over one drop directory would be a worse demo, not a better one. Ingestion is exposed as `POST /ingest` instead.
- **No API Manager, no authentication.** Same as the main POC.
- **No audit ledger, no comparator.** Those live in the POC namespace and were not duplicated. The prototype is about the application and data tiers, not about re-proving the fabric.
- **Six declarations and two manifests.** Enough to compare arithmetic. Nothing here says anything about throughput, and you should refuse to be drawn on performance from a dataset this size.

---

## Closing it

🗣 "This is not a proposal to change the tender. It is a demonstration that the per-module substitution your architecture already permits has a concrete option behind it — most plausibly for specific high-throughput paths identified during assessment, not as a wholesale replacement."

Then stop. Let them raise it if they want it.
