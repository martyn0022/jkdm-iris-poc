# Instructor's script
## JKDM / SMK · Unijaya technical enablement

Two parts, and nothing else:

1. **From git pull to ready** — the setup runbook. Do this before the room arrives.
2. **The attended demonstration** — what you run, and what you say, with people watching.

The attendee lab lives in `docs/EXERCISE.md` — fully worked, answers included, so nobody gets stranded. It is not in this document.
Both architectures — as shipped, and after the exercise — are drawn in `docs/architecture.html`.
Endpoint reference, if anyone asks what else the contract exposes: `docs/API.md`.

| Marker | Meaning |
|---|---|
| ▶ | Type this. Copy-paste ready — and always preceded by a line saying what it does and what to watch. |
| 🗣 | Say this. Paraphrase freely — the sequence matters more than the wording. |
| ⚠ | A place people get lost, or a claim not to overstate. |
| 🔧 | Recovery. |

---

# PART 1 · From git pull to ready

Budget **30 minutes** the first time on a machine, 5 minutes after that. Do it the day before if you can.

## 1.1 Get the code

Fresh machine — clone it.

▶
```bash
git clone <repo-url> jkdm-iris-poc && cd jkdm-iris-poc
```

Already cloned — pull, because the samples and scripts change more often than the code.

▶
```bash
cd jkdm-iris-poc && git pull
```

## 1.2 Environment file

Copies the defaults into `.env`. `-n` so it never overwrites a file you have already edited.

▶
```bash
cp -n .env.example .env
```

⚠ **IRIS runs on 52774, not the stock 52773.** A developer machine very often already has an IRIS holding 52773/1972, and the failure is ugly: every other container comes up healthy and only IRIS dies with `port is already allocated`. The defaults in `.env.example` avoid that fight. Every script reads `.env`; the portal URLs in this document do not, so if you change the port again, change them here too.

Nothing to configure for Apple silicon. Every image is multi-arch, the SFTP server included.

## 1.3 Build and start

Builds all five images and starts them in dependency order — Postgres, then the flat-file generator, then the backends, then IRIS.

▶
```bash
docker compose up -d --build
```

**8–12 minutes** on a cold machine — Laravel's composer install and the IRIS class compilation dominate. Seconds after that.

⚠ Docker needs roughly **10 GB free** in its VM. If it is full, the IRIS build fails in a way that reads like a product fault: `CreateDatabase` reports "no such directory" and the namespace never gets its interoperability mapping. Check with `docker system df` and reclaim with `docker builder prune -af` before you start debugging anything else.

## 1.4 Preflight

Runs 14 checks across every container, both backends, the contract, the routing table and the ingestion production. It waits for IRIS on its own, so run it as soon as the build finishes.

▶
```bash
./scripts/preflight.sh
```

Wait for `READY - 14 checks passed`. The script waits up to 90 seconds for IRIS on its own — the container reports healthy about 25 seconds before the web application and the production are actually up, so an impatient run would otherwise show four failures that fix themselves.

The check that matters most:

```
OK  the one-cent difference is live (COBOL 1088.47 / PHP 1088.46)
```

If that fails, the centrepiece of the demonstration is gone. Either the PHP container lost its Postgres settings, or somebody "fixed" the float arithmetic in `DutyController.php`. **Do not fix it — it is deliberate.**

## 1.5 Clean slate

Empties the audit trail, the comparison evidence, the partner drop and the acks, and puts the manifest route back to `LEGACY`. Nothing touches the seed data or anyone's code.

▶
```bash
./scripts/reset.sh
```

Clears the audit trail, the comparison evidence, the partner drop and the acks, and puts both routes back to LEGACY. Run it after any rehearsal.

## 1.6 Rehearse

Drives the entire demonstration unattended — ingestion, the fiscal refusal, all three modes, failure injection, the comparison. Two minutes. If it is green, the session will work.

▶
```bash
./scripts/dryrun.sh
```

Runs the whole thing unattended in about two minutes — ingestion, all three routing modes, failure injection, the comparator, and the manifest comparison. If this is green, the demonstration will work. Follow it with `./scripts/reset.sh`.

## 1.7 Open these tabs

Log in as `_SYSTEM` / `SYS` **now**, so you never log in in front of the room.

1. Production — `http://localhost:52774/csp/jkdmpoc/EnsPortal.ProductionConfig.zen?PRODUCTION=JKDM.Production`
2. Message viewer — `http://localhost:52774/csp/jkdmpoc/EnsPortal.MessageViewer.zen`
3. Event log — `http://localhost:52774/csp/jkdmpoc/EnsPortal.EventLog.zen`
4. **Intake process diagram** — `http://localhost:52774/csp/jkdmpoc/EnsPortal.BPLEditor.zen?BP=JKDM.BP.DeclarationIntake.BPL`
5. A terminal in the repo root

## 1.8 If setup breaks

| Symptom | Fix |
|---|---|
| Only IRIS fails, `port is already allocated` | Another IRIS owns 52773/1972. Change `IRIS_WEB_PORT`/`IRIS_SUPER_PORT` in `.env`. |
| IRIS build fails at `CreateDatabase` | Docker VM disk full. `docker builder prune -af`. |
| Preflight: PHP not computing | `docker logs jkdm-php-service`. Usually the `.env` DB settings — `laravel/entrypoint.sh` writes them at boot. |
| Preflight: production not running | `docker compose restart iris`, wait 90s, re-run preflight. |
| Files land in the drop and are never collected | `docker compose restart sftp` — bind-mount ownership. |
| The one-cent difference is gone | `git checkout laravel/` |
| Everything is wrong | `docker compose down && docker compose up -d --build` — about 10 minutes. |

---

# PART 2 · The attended demonstration

**Roughly 90 minutes** including discussion. Four segments, in this order — each one sets up the next.

**The thesis, in one sentence:** IRIS is the fabric — it inspects what arrives and routes it, and because it is the thing in the middle it can also tell you whether a routing change is safe.

Segments 2.1 and 2.2 are the routing story and carry the weight. Segment 2.3 is short on purpose: comparison is presented as a *consequence* of holding both answers, not as a migration-tooling pitch. Resist letting it expand — if the room wants to go deeper, that is a follow-up session, and saying so is stronger than improvising it.

Start from `./scripts/reset.sh`, with both routes on LEGACY.

---

## 2.1 · Flow A — ingestion and content-based routing  (35 min)

**What it proves:** IRIS is the client, the audit record precedes the parse, the fabric routes on what actually arrived, and "rejected" is not one outcome.

### Say the pattern before you touch a screen

🗣 "SFTP is not request/response. There is no inbound call for IRIS to route. IRIS is the *client* — it polls the partner's drop directory and pulls files down. The partner's 'push' is them uploading to their own server."

🗣 "That matters, because the routing diagram assumes there is an inbound request to route. Here there isn't. Everything downstream of the pull is an internally-originated transaction."

⚠ The FTP-as-client-pull pattern is from the SOW email, **not** the architecture document. Architecturally sound; say where it comes from.

### Show what the partner sends

Prints one of the sample files. You are showing them the raw wire format before any of it reaches IRIS — nothing is running yet.

▶
```bash
cat edi/samples/CUSDEC_K1-2026-000101.edi
```

🗣 "UN/EDIFACT CUSDEC. UNB is the interchange envelope, UNH opens the message, BGM carries the declaration reference, the LIN groups are the commodity lines. This is what arrives from DFTZ today via TIE Kinetix — §2.7, the ECS/EDI row in your catalogue."

⚠ **Say the X.400 gap here, plainly.** That catalogue row reads X.400 · SFTP. IRIS speaks SFTP and EDIFACT natively; it does **not** speak X.400. That needs a gateway or a partner-side change, and it is a real line item.

### The pull, live

Message viewer tab and terminal side by side.

This copies a file into the partner's drop directory. **That is all it does** — it is the partner uploading, not you calling IRIS. Nothing has invoked the fabric; it will notice on its next poll.

▶
```bash
./scripts/drop-edi.sh
```

🗣 "That was the partner uploading. Nothing has called IRIS. IRIS polls every five seconds."

A session appears within about **12 seconds**. Click it, then open the **visual trace**.

🗣 "Read it top to bottom. Service pulls the file. First call is to the audit operation — *before* anything tries to parse it. Then parse, transform to canonical, lodge, acknowledge."

Now switch to the **process diagram** tab.

🗣 "And here is that same flow as the developer sees it. This is not a picture of the code — it *is* the code; it compiles and runs. Notice the first box."

⚠ This is the strongest single moment in the segment. The audit-before-parse decision is not a claim in a comment — it is the first shape on the canvas, and step 2 is below it. Let them read the order themselves before you say anything else.

### Then point at shape 4 — the routing decision

🗣 "Step 2 only parses far enough to know *what arrived*. It does not transform anything. The next shape is the decision."

Shape **4 · Route on message type** has three branches: `CUSDEC · declaration`, `CUSCAR · manifest`, and `unknown type`.

🗣 "This is content-based routing, and it is the most ordinary thing a fabric does. Something arrives, the fabric looks inside it, and sends it to the handler for that kind of message. Every partner message type in your §2.7 catalogue is a branch here."

🗣 "Notice what that means for change. Adding a message type is a new branch on this diagram. The SFTP service does not change. The audit step does not change. The acknowledgement does not change. Nothing upstream or downstream knows a new type appeared."

⚠ Say plainly that the CUSCAR branch exists and is **wired but unfinished** — the routing decision is there, and so is the transform it calls; four lines inside that transform are blank. That is precisely the afternoon lab, and showing it now makes the brief take thirty seconds instead of five minutes.

### The point of the segment

🗣 "Look at the order. We wrote the audit record before we parsed. Why?"

Let someone answer. If nobody does:

🗣 "Because the file you cannot read is exactly the file you will be asked about. If a broker says they lodged at 09:14 and your parser rejected it, you need to prove what arrived and when. Parse first, and a bad file leaves you a stack trace and nothing else."

Reads the audit ledger — one row per file, whatever happened to it.

▶
```bash
./scripts/audit.sh
```

🗣 "Filename, SHA-256 of the raw bytes, size, partner, timestamp, outcome, and which backend priced it. The raw content is stored too — the original submission, not the parsed result."

### Two kinds of failure

Drops two files that will not lodge, then waits for the poll and reads the ledger again. Watch the `reason` column: the two rejects carry different codes.

▶
```bash
./scripts/drop-edi.sh bad && sleep 20 && ./scripts/audit.sh
```

- `CUSDEC_MALFORMED.edi` → `SYNTAX: no UNZ interchange trailer - file truncated in transit`
- `CUSDEC_UNPRICEABLE.edi` → `BUSINESS: core holds no declaration K1-2026-000902`

🗣 "Two rejections, two different people's problems. The first is the partner's software or a broken transfer — their IT fixes it. The second is a broker quoting a reference we do not hold — the broker fixes it. Report both as 'rejected' and somebody spends a morning working out which."

Now show the other half of the round trip — the file IRIS wrote back to the partner.

▶
```bash
cat sftp/outbound/CUSDEC_UNPRICEABLE.contrl
```

🗣 "A CONTRL with an action code and a short reason. Note what is *not* in it — no stack trace, no internal hostnames. That boundary is deliberate."

⚠ **Honest limitation.** IRIS parses EDIFACT structurally but does not ship the UN/EDIFACT D96A dictionary — those are licensed SEF files. So this validates the envelope, not full standards conformance, and the transform addresses fields by position rather than by name. With the SEF loaded it becomes a graphical DTL a business analyst can edit. Small cost, real cost, and it must land before the first partner conformance test.

🔧 Nothing appears: check the production tab is running. File sits in the drop uncollected: `docker compose restart sftp`.

---

## 2.2 · Flow B — the routing table as policy  (30 min)

**What it proves:** consumers depend on a contract, not an implementation — and the table that decides which implementation answers is a governance artefact, not just config.

⚠ **Framing.** This is a decoupling demo, not a migration demo. The ACOS-4 replatform and the COBOL-to-PHP conversion are contracted elsewhere; Figure 5.9.1 assigns IRIS one job in that programme — *"IRIS redirect as the switch"*, step 8. Demonstrate the switch, then hand operating it back to them explicitly.

### Before you type anything — what the room is looking at

**`curl` is not the demo. `curl` is the consumer.** It stands in for an agent's declaration system, the customs portal, another JKDM system — anything outside the fabric that calls a URL. The entire claim of this segment is *"the consumer does not change"*, and you cannot show that without a consumer in the room.

There are only three kinds of command, and it is worth naming them out loud:

| Command | What it is |
|---|---|
| `GET /routes` | **Reading the dial.** Shows the control surface before you touch it. |
| `PUT /routes/<op>/<mode>` | **Turning the dial.** The only thing that changes all segment. No deploy, no restart. |
| `GET /manifest/MANIFEST-2026-0044` | **The consumer call.** Byte-identical every single time. This is the thing that must not change. |

**And the headers are the trick.** A routing decision is invisible by design — that is its value. So the router stamps two response headers, purely so a human can see a decision that normally leaves no trace:

- `X-SMK-Route-Mode` — what the table said
- `X-SMK-Backend` — who actually answered

Strip them in production. Without them, three identical-looking curl calls would prove nothing on a projector.

Run the whole thing once end to end, then repeat the two interesting parts by hand.

▶
```bash
./scripts/demo.sh
```

That runs both halves. Walk it once, then repeat the interesting parts by hand.

### Half one — the operation the router refuses to move

Read the routing table first. This is the control surface — you are showing them the dial before touching it.

▶
```bash
curl -s http://localhost:52774/jkdm/routes | python3 -m json.tool
```

Two operations. `duty.calculate` is marked `"fiscal": 1` and reports `"modesAvailable": "LEGACY (locked - fiscal)"`.

▶ Try to move it:
```bash
curl -s -X PUT http://localhost:52774/jkdm/routes/duty.calculate/SHADOW
```

```
HTTP 409
duty.calculate is a fiscal operation and is locked to LEGACY (SMK 5.8)
```

🗣 "The router will not move it. Your own §5.8 says leave the revenue core in COBOL — *converting the core buys little and risks the numbers*. That sentence is usually a slide. Here it is a row in a table that refuses the request."

🗣 "And notice what that buys you for free. The operations you must never run twice — lodging a declaration, posting revenue — are exactly the fiscal ones. Locking them to LEGACY means the fabric never double-writes anything that moves money."

### Half two — the operation that is free to move

`manifest.lookup` computes nothing fiscal, so all three modes are open.

The loop does three things per pass: change the table, make the **same** consumer call, print who answered. Only the first of those three changes between passes.

▶
```bash
for m in LEGACY SHADOW LIVE_NEW; do
  curl -s -X PUT http://localhost:52774/jkdm/routes/manifest.lookup/$m >/dev/null
  curl -s -D- -o /dev/null http://localhost:52774/jkdm/manifest/MANIFEST-2026-0044 \
    | grep -i x-smk
done
```

You get three blocks. Read them as a table:

```
--- table now says LEGACY ---
X-SMK-ROUTE-MODE: LEGACY
X-SMK-BACKEND:    COBOL
body:  consignmentCount 3 | statusCode RL

--- table now says SHADOW ---
X-SMK-ROUTE-MODE: SHADOW
X-SMK-BACKEND:    COBOL          <- still COBOL
body:  consignmentCount 3 | statusCode RL      <- byte for byte identical

--- table now says LIVE_NEW ---
X-SMK-ROUTE-MODE: LIVE_NEW
X-SMK-BACKEND:    PHP            <- someone else answered
body:  consignmentCount 4 | statusCode RELEASED   <- and the answer changed
```

**Walk the room through it line by line — this is the segment.**

🗣 "Rows one and two. The table changed. The backend did not, and the body is identical. That is shadow mode working: PHP *was* called, its answer *was* thrown away, and the consumer cannot tell the difference. That is what makes it safe to switch on in production."

🗣 "Row three. Same URL, same caller, and now PHP answered — and look, the answer is different. Three consignments became four. `RL` became `RELEASED`."

🗣 "So: one URL that never changed, one table row that changed three times, and one moment where the answer moved. That last line is the entire risk of a migration, on screen, in a system where nobody has committed to anything yet."

| Mode | Who is called | Consumer gets |
|---|---|---|
| `LEGACY` | COBOL only | COBOL |
| `SHADOW` | COBOL **and** PHP | **COBOL.** PHP's answer is discarded. |
| `LIVE_NEW` | PHP only | PHP |

### Prove shadow cannot hurt the consumer

Puts the route in `SHADOW`, then breaks PHP outright — it now returns HTTP 500 on every call.

▶
```bash
curl -s -X PUT http://localhost:52774/jkdm/routes/manifest.lookup/SHADOW
./scripts/php-fail.sh on
```

▶ Call the manifest endpoint again — still served by COBOL, still on time.

🗣 "PHP is returning 500. The consumer never finds out. In shadow mode the new implementation cannot hurt anybody — that is what makes it safe to run against live traffic."

Put PHP back before you move on.

▶
```bash
./scripts/php-fail.sh off
```

⚠ Do not forget this.

### The moment worth pausing on

In `LIVE_NEW` the manifest answer visibly changes: `consignments 3 → 4`, `status RL → RELEASED`.

🗣 "That is what moving a backend looks like from outside. The contract held, the URL held — and the answer changed. Which is the whole reason the middle mode exists."

▶ Put it back:
```bash
curl -s -X PUT http://localhost:52774/jkdm/routes/manifest.lookup/LEGACY
```

---

## 2.3 · Why the lock is there  (10 min)

**What it proves:** the fiscal lock is not caution for its own sake. There is a specific, reproducible reason.

⚠ **Framing, and it matters.** This is not InterSystems offering to do migration assurance — that is Unijaya's deliverable. Ten minutes, then move on.

🗣 "I just told you the router refuses to move the duty calculation. Let me show you why that is not paranoia."

▶ Ask each implementation the same question. `duty.calculate` is LEGACY, so the contract gives you COBOL's answer; PHP is called directly.
```bash
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"declarationRef":"K1-2026-000104"}' \
  http://localhost:52774/jkdm/duty/calculate | grep -o '"totalDutyAmount":[0-9.]*'

curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"declarationRef":"K1-2026-000104"}' \
  http://localhost:8082/duty/calculate | grep -o '"totalDutyAmount":[0-9.]*'
```

Two answers to the same question:

```
COBOL   totalDutyAmount 1088.47
PHP     totalDutyAmount 1088.46
```

### The cent

🗣 "One cent, on one declaration. COBOL rounds each line to two decimals in packed decimal, then adds up. PHP adds at full float precision and rounds once at the end. Seven lines, one cent."

⚠ Nobody planted it. That is the genuine behaviour of fixed-point versus binary floating-point arithmetic.

**Then put their own document on screen.** §5.7 carries this in a warning box:

> **"Money is decimal, never floating point.** COBOL packed-decimal fields (for example `PIC S9(9)V99 COMP-3`) map to integer minor units or arbitrary-precision decimals with explicit rounding, **never to native floats**. This governs duty, tax, penalties and payment reconciliation."

🗣 "Your architecture names the exact field type and prohibits the exact mistake. And it still happened, in a codebase written by people who had read it. That is the argument for the gate being mechanical rather than a review checklist."

🗣 "That is why the router refuses to move it. Not policy for its own sake — this."

⚠ Optional, ten seconds, and it lands well: show what COBOL actually returned before the fabric touched it. This calls the COBOL container directly, bypassing IRIS.

▶
```bash
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"declarationRef":"K1-2026-000104"}' http://localhost:8081/duty/calculate
```

🗣 "Positional, zero-padded, no field names. The cent is in there — characters 39 to 51. Normalising that into the JSON you just saw is the fabric doing its day job."

⏱ **Stop here.** Do not open the comparator, the classification scheme, the FTA boundary case or the timezone argument. Those belong to the afternoon, on the manifest, where the room does the judging instead of watching you do it.

⚠ If someone asks who owns proving equivalence: **characterisation tests belong to whoever converts the module**, the thresholds belong to JKDM (§5.7 is explicit — *"defines the method; it does not set the thresholds"*), and the fabric's only contribution is that in shadow mode both answers exist in one place at one moment. Say that and move on — it is a boundary worth being crisp about.

---

## 2.4 · Where the router applies, and where it stops  (10 min)

**What it proves:** the routing decision covers file-origin traffic too — and the fiscal lock is what keeps that safe.

### It is the same table for files

Nothing to configure — Flow A already lodged over the same contract this morning. This view joins the ingestion ledger to the comparison evidence, so you can see file-origin traffic and its routing outcome together.

▶
```bash
./scripts/audit.sh combined
```

🗣 "Those declarations arrived as EDIFACT files from a partner. They were lodged through the same contract an interactive consumer calls, so they obeyed the same routing table. File traffic is not a special case."

⚠ Be straight that this was a decision:

🗣 "Your document does not say whether file and batch traffic get the same routing as live API calls — §5.2 is silent. I made it yes, because it is one table and two doors into it. That is JKDM's call to confirm, not mine."

### Where it stops

🗣 "One honest limitation, and it is a property of the mechanism rather than of either backend."

🗣 "Shadow mode discards the *response*. It cannot discard the *side effect*. Shadow an operation that writes — lodging a declaration, posting revenue — and you have written twice. Throwing away the second answer undoes nothing."

Then the resolution, which is already on screen from 2.2:

🗣 "Which is why fiscal operations are locked. The operations that must never run twice are the ones that move money, and those are exactly the ones the router refuses to shadow. The problem is designed out rather than managed."

⚠ **Do not overclaim.** Say what is still open:

- The `Fiscal` flag is a proxy for "has side effects", and the two are not the same thing. A non-fiscal operation that *wrote* would be double-written, because the router calls the second backend unconditionally and cannot tell a read from a write.
- **Nothing in this POC writes**, so it cannot happen here and you cannot show it. Say so if asked — a write-free operation was chosen deliberately so that shadow mode was safe to demonstrate at all.
- Whoever declares an operation fiscal is making that judgement by hand. There is no checker.

🗣 "So the honest position: the dangerous cases are closed by policy, and the general problem is not solved. If you want it solved, the flag stops being about money and starts being about side effects — and somebody has to classify every operation."

🔧 If someone asks to see the double-write: you cannot, and that is the right answer. Nothing here writes. Show them the line instead — `StranglerRouter` calls the second backend unconditionally in SHADOW, and it has no way of knowing whether that call has side effects.

⏱ If this catches fire, let it run. It is a better conversation than anything it would displace.

---

## Close

Leave the environment clean for whoever picks it up next — including you tomorrow.

▶
```bash
./scripts/reset.sh
```

Five open questions worth naming before you finish — all of them from their document or arising from it, none of them blockers:

1. **How does IRIS invoke Visual COBOL?** Undecided. Four options, very different latency and transactional characteristics. Today's HTTP wrapper is POC convenience, not a recommendation.
2. **Does file and batch traffic get strangler routing?** §5.2 is silent. The POC says yes.
3. **Shadow mode on writes.** No clean answer. Pick one before Wave 2.
4. **X.400.** In the estate per §2.7, not native to IRIS.
5. **D96A SEF schemas.** Not in the product; needed before partner conformance testing.

---

## Command reference

```bash
./scripts/preflight.sh                    # 14 checks, waits for IRIS
./scripts/reset.sh                        # clean slate, both routes LEGACY
./scripts/dryrun.sh                       # unattended rehearsal, ~2 min
./scripts/demo.sh                         # fiscal lock + three modes on the manifest
./scripts/drop-edi.sh [all|bad|manifest|K1-2026-000104]
./scripts/audit.sh [equivalence|diffs|combined|m-diffs]
./scripts/php-fail.sh [on|hang|off]

curl -X PUT http://localhost:52774/jkdm/routes/manifest.lookup/SHADOW   # allowed
curl -X PUT http://localhost:52774/jkdm/routes/duty.calculate/SHADOW    # 409, fiscal
curl -s http://localhost:52774/jkdm/routes
```
