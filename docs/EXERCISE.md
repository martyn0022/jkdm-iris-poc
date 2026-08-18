# Guided lab
## Getting vessel manifests through the fabric

**We do this together, step by step.** The instructor runs each step on screen, then waits. Nobody works ahead.

**Every answer is printed in this document.** Nothing is hidden. If you would rather read the answer and understand it than guess at it, do that — the point of this afternoon is not to test whether you can find a bracket.

**You paste four lines, in Part 1.** That is the entire coding requirement — Part 2 is a browser and a button.

---

## What the afternoon is about

Two separate things, and it is worth knowing which is which before we start.

**Part 1 — teach the fabric a new message.**
Partners send several kinds of EDI file. The fabric understands customs declarations already. It does not understand vessel manifests, so it rejects them. We teach it, by pasting in four lines that say where to find four pieces of information inside the file. The slides explain what changes inside the fabric when we do.

**Part 2 — see the switch that moves an operation between implementations.**
A console, three buttons, and the evidence that shadow mode produces. No code, and no decisions — those are made elsewhere.

---

# PART 1 · Teach the fabric to read a manifest

Five steps. One paste. Roughly twenty minutes including the discussion.

---

### Step 1 — See the problem

**Why:** see the failure yourself, so you know what "fixed" looks like.

**Do this:**
```bash
./scripts/reset.sh
./scripts/drop-edi.sh manifest
sleep 15
./scripts/audit.sh
```

*Or, if you have the console open at `http://localhost:52774/jkdm/console`: click **Reset to a clean start**, then **Drop a CUSCAR manifest**, wait, then **Ingestion trail**. Same three things.*

**You should see:**
```
CUSCAR_MANIFEST.edi    REJECTED    0
    reason: UNSUPPORTED: manifest handler not finished - see docs/EXERCISE.md
```

**What that means:** the fabric collected the file, recorded that it arrived, and told the partner it could not process it. It already knows the file *is* a manifest — it just has nothing to do with one yet. That last part is what we are adding.

---

### Step 2 — Look at what the partner sent

**Why:** you are about to map four values out of this file. Worth seeing them first.

**Do this:**
```bash
cat edi/samples/CUSCAR_MANIFEST.edi
```

Fourteen lines. These four carry what we need:

```
BGM+85+MANIFEST-2026-0041+9                                        <- the reference
TDT+20+VOY-8841+1++CARRIER:172:20++++9V-8841:103:11:MV BINTANG SATU <- the vessel
LOC+11+MYPKG:139:6                                                 <- the port
DTM+132:202608200600:203                                           <- the arrival
```

**How a line is built.** A three-letter tag, then **elements** separated by `+`, and an element can hold **components** separated by `:`.

```
BGM  +  85  +  MANIFEST-2026-0041  +  9
 |      |            |                |
tag    el.1        el.2            el.3
```

So the manifest reference is **element 2 of BGM**. There are no field names in the file — meaning comes from position. *(The slides cover why, and what changes when the message dictionary is licensed.)*

---

### Step 3 — Paste the mapping

**Why:** this is the whole code change. Four lines, pasted in one go.

**Open:** `iris/src/JKDM/Xform/CuscarToCanonical.cls`

Find the marked block in the middle:

```
        // ========================================================
        //   PASTE THE FOUR LINES FROM THE LAB SHEET HERE
        // ========================================================
```

**Paste this between the two lines of `=`:**

```objectscript
        Set pCanonical.ManifestRef  = ##class(JKDM.Util.EdifactNav).Get(pDoc, "BGM", 2)
        Set pCanonical.VesselID     = ##class(JKDM.Util.EdifactNav).Get(pDoc, "TDT", 9, 1)
        Set pCanonical.PortOfEntry  = ##class(JKDM.Util.EdifactNav).Get(pDoc, "LOC", 2, 1)
        Set pCanonical.ETA          = ##class(JKDM.Util.EdifactNav).DateTime(##class(JKDM.Util.EdifactNav).Get(pDoc, "DTM", 1, 2, 2))
```

⚠ **Keep the indentation.** ObjectScript reads a line that starts at the very left margin as a *label*, not as code. If your pasted lines end up hard against the left edge you will get four errors saying `Invalid command`. The fix is simply to indent them — line them up with the lines above the marker.

Save the file. That is all the code you write in Part 1.

**What each line says**, reading left to right — *from this document, get this segment, this element*:

| Line | Reads | From the file | Result |
|---|---|---|---|
| 1 | BGM, element 2 | `BGM+85+MANIFEST-2026-0041+9` | `MANIFEST-2026-0041` |
| 2 | TDT, element 9, **component 1** | `...9V-8841:103:11:MV BINTANG SATU` | `9V-8841` |
| 3 | LOC, element 2, component 1 | `LOC+11+MYPKG:139:6` | `MYPKG` |
| 4 | DTM, element 1, component 2, **second DTM** | `DTM+132:202608200600:203` | `2026-08-20T06:00:00+08:00` |

Line 2 and 3 add a third number because the value sits inside a component. Line 4 adds a fourth number because there are two `DTM` segments and the arrival is the second — then `DateTime()` turns `202608200600` into a real timestamp.

---

### Step 4 — Load it into IRIS

**Why:** the file on disk means nothing until IRIS compiles it, and the running flow keeps its own compiled copy in memory.

**Do this** — both blocks:

```bash
docker cp iris/src jkdm-iris:/opt/jkdm/ && echo 'do $system.OBJ.LoadDir("/opt/jkdm/src","ck",,1) halt'   | docker exec -i jkdm-iris iris session IRIS -U JKDMPOC
```

```bash
echo 'do ##class(Ens.Director).StopProduction(10,1) do ##class(Ens.Director).StartProduction("JKDM.Production") halt'   | docker exec -i jkdm-iris iris session IRIS -U JKDMPOC
```

**You should see** `Compiling class JKDM.Xform.CuscarToCanonical` with **no ERROR lines** beneath it.

**If it errors:** almost always a missing `)` or `"`. Line 4 has three closing brackets; the others have two.

**Skip the second block and nothing will change** — the flow will still be running the old, empty version.

---

### Step 5 — Watch it work

**Do this:**
```bash
./scripts/reset.sh
./scripts/drop-edi.sh manifest
sleep 15
./scripts/audit.sh
```

*Or, if you have the console open at `http://localhost:52774/jkdm/console`: click **Reset to a clean start**, then **Drop a CUSCAR manifest**, wait, then **Ingestion trail**. Same three things.*

**You should see:**
```
CUSCAR_MANIFEST.edi    LODGED    MANIFEST-2026-0041    1    COBOL    CORE-MANIFEST-2026-0041
```

**What that means:** the fabric now handles a message type it rejected twenty minutes ago. Nothing about collection, auditing or acknowledgement changed — you added a translation, not a pipeline.

**Now run the slides** — the lab section of `docs/session-deck.html` — which walk through what happened inside the fabric to make that possible.

---

### Checkpoint discussion

> The manifest describes **one vessel carrying many consignments**. Our canonical message was built around **one declaration**, so the consignments were discarded.
>
> Is that acceptable? What downstream use would break — and who should have decided that, us or JKDM?

---

# PART 2 · The toggle, and what it produces

**Fifteen minutes. No code, and no decisions to make.**

## Read this first — what this part is *not*

Your new message type is finished. Whether the manifest lookup is answered by COBOL or by PHP is a **completely separate question**, and it was already being asked before your message type existed.

This part shows you **the switch**, and what the switch produces. That is all.

**It is not a validation exercise.** Deciding whether the PHP implementation is good enough to go live happens elsewhere and long before anyone touches this toggle:

| Activity | Who | When |
|---|---|---|
| Characterisation tests, unit tests, UAT | Whoever converted the module | Before deployment |
| Deciding what counts as equivalent, and the tolerances | **JKDM** — §5.7 is explicit that the architecture *"defines the method; it does not set the thresholds"* | Governance, before cutover |
| Reading the evidence, passing or failing the wave | The programme | At the gate |
| **Flipping the switch once that is decided** | **This console** | Deployment |

So by the time you are here, someone has already decided. **IRIS's job is to make that decision easy to apply and instantly reversible.**

---

### Step 6 — Open the console

**Why:** the routing table is the control surface for the whole transition. Driving it from a terminal makes it look like a developer toy; it is not.

**Open in a browser:**

```
http://localhost:52774/jkdm/console
```

**You should see** panels on the left and a **terminal on the right**. Everything you click prints the `curl` it runs before it runs it — so nothing here is hidden, and you can copy any command out and run it yourself. That is worth thirty seconds of your attention: it is the difference between a control panel you trust and one you don't.

In the **Flow B · the routing table** panel, two operations:

- **`duty.calculate`** — badged `FISCAL · LOCKED`, with `SHADOW` and `LIVE_NEW` greyed out. The router refuses to move it. That is §5.8 — *leave the revenue core in COBOL* — as configuration rather than convention.
- **`manifest.lookup`** — all three modes available, because it moves no money.

⚠ You do not need the other panels for this exercise. They are the morning's demonstration, left in place so you can replay any of it.

---

### Step 7 — Flip it

**Why:** so you see what a cutover actually costs.

Click **`SHADOW`** on `manifest.lookup`, then **`LIVE_NEW`**, then back to **`LEGACY`**.

Watch the *"answered by"* line change between `COBOL` and `PHP`.

**What that means:**

| Mode | Who is called | The consumer receives |
|---|---|---|
| `LEGACY` | COBOL only | COBOL |
| `SHADOW` | COBOL **and** PHP | **COBOL.** PHP's answer is discarded. |
| `LIVE_NEW` | PHP only | PHP |

No deployment. No consumer change. No release. **And the rollback is the same click.**

Now try clicking `SHADOW` on `duty.calculate`. It refuses, and the terminal shows you exactly how:

```
HTTP 409
{"error":"duty.calculate is a fiscal operation and is locked to LEGACY",
 "policy":"fiscal","reference":"SMK 5.8"}
```

**409, not 400.** The request was understood and refused on policy — not rejected as malformed. The distinction is deliberate: a caller can tell "you may not" apart from "you asked wrong".

---

### Step 8 — See what SHADOW produces

**Why:** this is the artefact the switch generates, and the reason `SHADOW` exists as a middle mode at all.

Put `manifest.lookup` back into **`SHADOW`**, then drop your manifest again:

```bash
./scripts/drop-edi.sh manifest
```

*Or click **Drop a CUSCAR manifest** in the console.*

Within about fifteen seconds the **Comparison evidence** table at the bottom of the console fills in.

For the field-level detail:

```bash
./scripts/audit.sh m-diffs
```

*Or click **Manifest differences** in the console's **Evidence** panel — it is the same report either way, printed by the same code.*

**Five differences** between the two implementations:

```
vesselName                    padded to 30 chars   / trimmed
eta                           +08:00               / +00:00
statusCode                    RL                   / RELEASED
consignments[0].description   truncated at 40      / full text
backend                       COBOL                / PHP
```

**What that means.** In `SHADOW`, one component held both answers at the same moment — and nothing else in the estate ever does. COBOL never sees PHP's answer; PHP never sees COBOL's. So if anyone is going to ask whether they agree, the fabric is the only place it can be asked.

**What the fabric does not do is decide.** Which of those five matter is a judgement made by the people converting the module and approved by JKDM. It arrives back here as one small configuration class — `JKDM.Rule.ManifestEquivalence` — which sorts each field into fiscal, material or ignorable so the report is readable.

Have a look at it if you like. You are not filling it in today.

---

### Close the loop

Put it back:

```bash
curl -s -X PUT http://localhost:52774/jkdm/routes/manifest.lookup/LEGACY
```

or just click **`LEGACY`** in the console.

---

## What you actually did today

You pasted four lines and taught the fabric a message type it had never seen — without touching collection, auditing, acknowledgement, the routing table, either backend or the database.

Then you saw the switch that moves an operation between two implementations, and the evidence that switch produces on the way.

**The part worth carrying out of the room:** adding a partner message is a branch and a handful of coordinates. Moving a backend is one click and one row. Neither is a project. What *is* hard — deciding whether the new implementation is good enough — happens elsewhere, and no amount of tooling decides it for you.

---

## If something goes wrong

| Symptom | Cause |
|---|---|
| `Invalid command : 'pCanonical...'` | The pasted lines are hard against the left margin. ObjectScript needs them indented — see the warning in Step 3. |
| Console shows nothing under the operations | IRIS is still starting. Wait, then reload. |
| No comparison appears in Step 8 | The route is not in `SHADOW`, or the file was dropped under a name already used. |
| Other compile error after pasting | Missing `)` or `"`. The fourth line has three closing brackets. |
| Still `UNSUPPORTED` after reloading | The production was not restarted — Step 4, second command. |
| `LODGED` but fields look empty | Only part of the block was pasted. All four lines go in together. |
| Nothing happens when you drop a file | Same filename as a previous attempt. The collector skips files it already failed on — use a new name. |

**Start completely over:**
```bash
git checkout iris/src/JKDM/Xform/CuscarToCanonical.cls
docker compose up -d --build iris
./scripts/reset.sh
```
