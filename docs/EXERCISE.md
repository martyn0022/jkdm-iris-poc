# Guided lab
## Getting vessel manifests through the fabric

**We do this together, step by step.** The instructor runs each step on screen, then waits. Nobody works ahead.

**Every answer is printed in this document.** Nothing is hidden. If you would rather read the answer and understand it than guess at it, do that — the point of this afternoon is not to test whether you can find a bracket.

**You will type six lines of code in total.** Four in Part 1, two in Part 2.

---

## What the afternoon is about

Two separate things, and it is worth knowing which is which before we start.

**Part 1 — teach the fabric a new message.**
Partners send several kinds of EDI file. The fabric understands customs declarations already. It does not understand vessel manifests, so it rejects them. We teach it, by filling in four blanks that say where to find four pieces of information inside the file.

**Part 2 — decide whether a new implementation can be trusted.**
This one needs more explaining, and it is the part that actually matters. See the section before Step 8.

---

# PART 1 · Teach the fabric to read a manifest

---

### Step 1 — See the problem

**Why:** before changing anything, see the failure with your own eyes so you know what "fixed" looks like.

**Do this:**
```bash
./scripts/reset.sh
./scripts/drop-edi.sh manifest
sleep 15
./scripts/audit.sh
```

**You should see:**
```
CUSCAR_MANIFEST.edi    REJECTED    0
    reason: UNSUPPORTED: manifest handler not finished - see docs/EXERCISE.md
```

**What that means:** the fabric did its job — it collected the file from the partner, recorded that it arrived, and told the partner it could not process it. It simply does not know what a manifest contains. That is what we are fixing.

---

### Step 2 — Look at what the partner sent

**Why:** you cannot map a file you have not read.

**Do this:**
```bash
cat edi/samples/CUSCAR_MANIFEST.edi
```

**You should see** fourteen lines. Only four of them matter today:

```
BGM+85+MANIFEST-2026-0041+9
TDT+20+VOY-8841+1++CARRIER:172:20++++9V-8841:103:11:MV BINTANG SATU
LOC+11+MYPKG:139:6
DTM+132:202608200600:203
```

**What that means — how to read a segment.** Every line is a *segment*. It starts with a three-letter tag, then **elements** separated by `+`. An element can hold **components** separated by `:`.

```
BGM  +  85  +  MANIFEST-2026-0041  +  9
 |      |            |                |
tag    el.1        el.2            el.3
```

So the manifest reference is **element 2 of the BGM segment**. That is the whole idea, and the four blanks you fill in are all this same idea.

---

### Step 3 — Open the file you will edit

**Why:** so you can see that most of the work is already done.

**Open:** `iris/src/JKDM/Xform/CuscarToCanonical.cls`

Scroll to the middle. You will find:

- **Six finished lines** near the top — your worked examples
- **Four blocks marked `TODO`**, each with a comment saying which segment it needs

You are only adding four lines. Nothing else in the file changes.

---

### Step 4 — Fill in TODO 1 (instructor does this one)

**Why:** the manifest reference is how everything downstream identifies this manifest. Without it the fabric has an anonymous document.

**The answer:**
```objectscript
Set pCanonical.ManifestRef = ##class(JKDM.Util.EdifactNav).Get(pDoc, "BGM", 2)
```

**Read it left to right:** *from this document, get the BGM segment, element 2.*

`EdifactNav` is a small helper that ships with the POC. `Get` takes the document, a segment tag, and an element number.

**Type it in**, replacing the commented `// Set pCanonical.ManifestRef = ...` line.

---

### Step 5 — Fill in TODO 2, 3 and 4

**Why:** the same idea three more times. Only the segment and the numbers change.

**The answers:**

```objectscript
// TODO 2 — the vessel identifier
Set pCanonical.VesselID = ##class(JKDM.Util.EdifactNav).Get(pDoc, "TDT", 9, 1)

// TODO 3 — the port of discharge
Set pCanonical.PortOfEntry = ##class(JKDM.Util.EdifactNav).Get(pDoc, "LOC", 2, 1)

// TODO 4 — the estimated arrival
Set pCanonical.ETA = ##class(JKDM.Util.EdifactNav).DateTime(##class(JKDM.Util.EdifactNav).Get(pDoc, "DTM", 1, 2, 2))
```

**Why each one looks the way it does:**

| | Reading from | Extra numbers |
|---|---|---|
| **TODO 2** | `TDT+...++++9V-8841:103:11:MV BINTANG SATU` | A **third** number picks a component. Element 9, component 1 → `9V-8841`. |
| **TODO 3** | `LOC+11+MYPKG:139:6` | Element 2, component 1 → `MYPKG`. |
| **TODO 4** | `DTM+132:202608200600:203` | A **fourth** number picks *which* DTM — there are two, and the arrival is the second. `DateTime()` then turns `202608200600` into a proper timestamp. |

TODO 4 is the only awkward one. Copy it exactly.

---

### Step 6 — Load your change into IRIS

**Why:** the file on your disk means nothing until IRIS compiles it. Two commands: compile, then restart the flow so it picks up the new code.

**Do this** — copy both blocks in full:

```bash
docker cp iris/src jkdm-iris:/opt/jkdm/ && \
echo 'do $system.OBJ.LoadDir("/opt/jkdm/src","ck",,1) halt' \
  | docker exec -i jkdm-iris iris session IRIS -U JKDMPOC
```

```bash
echo 'do ##class(Ens.Director).StopProduction(10,1) do ##class(Ens.Director).StartProduction("JKDM.Production") halt' \
  | docker exec -i jkdm-iris iris session IRIS -U JKDMPOC
```

**You should see** `Compiling class JKDM.Xform.CuscarToCanonical` with **no ERROR lines** under it.

**If you get an error:** it is almost always a missing `)` or `"`. TODO 4 has three closing brackets; the others have two. Compare with the finished lines above your TODOs.

**Why the restart matters:** the running flow holds a compiled copy of your code in memory. Skip the restart and your correct change will look like it did nothing.

---

### Step 7 — Watch it work

**Do this:**
```bash
./scripts/reset.sh
./scripts/drop-edi.sh manifest
sleep 15
./scripts/audit.sh
```

**You should see:**
```
CUSCAR_MANIFEST.edi    LODGED    MANIFEST-2026-0041    1    COBOL    CORE-MANIFEST-2026-0041
```

**What that means:** the fabric now reads a message type it could not read fifteen minutes ago. Notice what did *not* change — the same collection from the partner, the same audit record, the same acknowledgement. You added a translation, not a pipeline.

---

### Checkpoint discussion

> The manifest describes **one vessel carrying many consignments**. Our canonical message was designed around **one declaration**. What happened to the consignment detail?

*(We kept the manifest header and dropped the individual consignments. Is that acceptable? What downstream use would break?)*

---

# PART 2 · Can the new implementation be trusted?

## Read this before Step 8 — what we are actually doing

This part confuses people the first time, so here it is in plain terms.

**There are two programs that do the same job.**

JKDM's manifest lookup exists twice. Once in **COBOL**, on the old system. Once in **PHP**, written as part of the modernisation. Both are running right now, on your machine, and both can answer *"tell me about manifest MANIFEST-2026-0041."*

**Eventually JKDM wants to switch off the COBOL one.** Before anyone can do that, somebody has to answer a question that sounds simple and is not:

> Do the two programs actually give the same answers?

**"Shadow mode" is how you find out without risk.** You tell IRIS to send every request to *both* programs. The consumer gets the COBOL answer — the trusted one, the one that has been right for twenty years. The PHP answer is thrown away. But before throwing it away, IRIS compares the two, field by field, and records every difference.

Nobody is affected. Nothing depends on the PHP answer. You are collecting evidence on live traffic.

**Then comes the hard part, which is not technical.** The comparison will find differences — it always does. Some are meaningless. Some are serious. Somebody has to say which is which, and that decision is what determines whether the new program is allowed to go live.

That decision is what you are making this afternoon.

**Three things worth knowing:**

- **This is not testing IRIS.** IRIS is the thing doing the comparing. You are judging the two backends.
- **FISCAL / MATERIAL / IGNORE is not IRIS terminology.** It is a scheme this POC invented to sort differences by seriousness. You could pick different buckets.
- **The architecture deliberately does not tell you the answer.** SMK §5.7 says it *"defines the method; it does not set the thresholds"* — JKDM approves those before cutover. So the judgement genuinely is yours to make and defend.

---

### Step 8 — Turn on shadow mode and compare

**Why:** to generate the evidence you are about to judge.

**Do this:**
```bash
./scripts/reset.sh
curl -s -X PUT http://localhost:52774/jkdm/routes/manifest.lookup/SHADOW
./scripts/drop-edi.sh manifest
sleep 15
./scripts/audit.sh m-diffs
```

⚠ **Order matters.** `reset.sh` puts the route back to normal, so it has to run *before* you switch shadow mode on. Run them the other way round and nothing is compared.

**What each line does:**

| Line | What it does |
|---|---|
| `reset.sh` | Clears previous results so you see only your own |
| `curl ... /SHADOW` | Tells IRIS: from now on, ask both programs |
| `drop-edi.sh manifest` | The partner uploads the manifest file again |
| `audit.sh m-diffs` | Shows every difference found between the two answers |

**You should see five differences.**

---

### Step 9 — Understand the five differences

```
vesselName                    MV BINTANG SATU (30 chars) / MV BINTANG SATU
eta                           2026-08-20T06:00:00+08:00  / 2026-08-19T22:00:00+00:00
statusCode                    RL                         / RELEASED
consignments[0].description   truncated at 40 chars      / full text
backend                       COBOL                      / PHP
```

Left is COBOL, right is PHP. What is happening in each:

| Field | What is going on |
|---|---|
| `vesselName` | COBOL fields are fixed width. The name is padded out to 30 characters with spaces. PHP trims it. |
| `eta` | **Both are the same moment.** 06:00 in Malaysia is 22:00 the previous day in UTC. COBOL reports local time, PHP reports UTC. |
| `statusCode` | COBOL returns the code as stored. PHP looks it up and returns the friendly label. |
| `description` | COBOL truncates text at 40 characters. PHP returns all of it. |
| `backend` | The field that tells you which program answered. Of course it differs. |

---

### Step 10 — Classify them

**Why:** because a list of differences is useless until somebody says which ones block the migration.

**The three buckets:**

| Bucket | Meaning | Consequence |
|---|---|---|
| **FISCAL** | Money or legal status is wrong | The module **fails**. Nobody switches. |
| **MATERIAL** | A genuine defect, but no money moves | Raise it, fix it, do not block on it |
| **IGNORE** | Expected to differ. Not a defect | No action |

**Here is one defensible answer.** It is not the only one — argue with it.

| Field | Proposed | Reasoning |
|---|---|---|
| `vesselName` | **MATERIAL** | Padding is a parser flaw, not a data flaw. The name is not *wrong*, it is ugly. Fix the parser, do not block cutover. |
| `eta` | **argue** | Same instant, written differently. Harmless — unless a downstream system reads the date and ignores the timezone, in which case it is an eight-hour error on a vessel arrival. |
| `statusCode` | **argue** | `RL` and `RELEASED` mean the same thing. But **release status is named in the §5.7 fiscal list.** A strict reading says any difference in a fiscal field fails. |
| `description` | **MATERIAL** | Information is lost. No money moves. Somebody downstream may still be relying on the full text. |
| `backend` | **IGNORE** | It exists precisely to differ. If it ever matched, something would be broken. |

**Discuss the two marked "argue" as a room.** They have no correct answer, and that is the finding — not a gap in the exercise.

The question underneath both: *who decides, and where is that decision written down?* Today, nowhere. That is what §5.7 is asking JKDM to fix before cutover.

---

### Step 11 — Turn your decision into code

**Why:** so the comparator applies your judgement automatically, to every manifest, forever — instead of a person re-reading a spreadsheet.

**Open:** `iris/src/JKDM/Rule/ManifestEquivalence.cls`

Find `Classify`. It has two commented `TODO` lines. **This is the answer if the room decides `statusCode` is fiscal:**

```objectscript
If ..InList(tField, "statusCode") { Quit "FISCAL" }
If ..InList(tField, "backend,retrievedAt") { Quit "IGNORE" }
```

**Reading it:** if the field being compared is `statusCode`, call it FISCAL. If it is `backend` or `retrievedAt`, call it IGNORE. Anything not named falls through to MATERIAL, which is the safe default — an unclassified difference is treated as a defect rather than waved through.

Put more than one field in a bucket by comma-separating them.

**Then reload and restart, same two commands as Step 6:**

```bash
docker cp iris/src jkdm-iris:/opt/jkdm/ && \
echo 'do $system.OBJ.LoadDir("/opt/jkdm/src","ck",,1) halt' \
  | docker exec -i jkdm-iris iris session IRIS -U JKDMPOC

echo 'do ##class(Ens.Director).StopProduction(10,1) do ##class(Ens.Director).StartProduction("JKDM.Production") halt' \
  | docker exec -i jkdm-iris iris session IRIS -U JKDMPOC
```

---

### Step 12 — See your judgement applied

**Do this:**
```bash
./scripts/reset.sh
curl -s -X PUT http://localhost:52774/jkdm/routes/manifest.lookup/SHADOW
./scripts/drop-edi.sh manifest
sleep 15
./scripts/audit.sh m-diffs
./scripts/audit.sh m-equivalence
```

**You should see** the same five differences, now labelled with your decision — and a verdict:

```
statusCode    FISCAL     RL / RELEASED
backend       IGNORE     COBOL / PHP
...
Equivalence rate, manifest.lookup: 0.00% (0/1)
Breakdown: FISCAL_DIFF=1
```

**What that means:** because the room called `statusCode` fiscal, this manifest now **fails the gate**. Had you called it `IGNORE`, the same comparison would have passed.

Nothing about the two programs changed between those two outcomes. Only your judgement did. That is the whole point of the afternoon.

---

## What you actually did today

You typed six lines. That was never the difficult part.

The difficult part was Step 10, and it took the whole room. Sorting differences into "blocks the migration" and "does not" is the judgement this programme will make hundreds of times, and it decides whether each module passes its gate — not whether the code compiles.

Nothing you argued about in Step 10 was ObjectScript.

---

## If something goes wrong

| Symptom | Cause |
|---|---|
| Compile error on a TODO line | Missing `)` or `"`. TODO 4 has three closing brackets. |
| Still `UNSUPPORTED` after reloading | The production was not restarted — Step 6, second command. |
| `LODGED` but fields look empty | Only TODO 1 was filled in; it is the one the check looks at. |
| Nothing happens when you drop a file | Same filename as a previous attempt. The collector skips files it already failed on — use a new name. |
| No differences in Step 8 | Shadow mode was set *before* `reset.sh`, so it was switched back off. |

**Start completely over:**
```bash
git checkout iris/src/JKDM/Xform/CuscarToCanonical.cls
git checkout iris/src/JKDM/Rule/ManifestEquivalence.cls
docker compose up -d --build iris
./scripts/reset.sh
```
