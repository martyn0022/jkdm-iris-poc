"""
JKDM SMK POC - generate UN/EDIFACT CUSDEC sample files from Postgres.

WHY GENERATED RATHER THAN HAND-WRITTEN
--------------------------------------
The EDI samples and the COBOL flat file are both derived from the same
seed tables. If they were written by hand they would drift, and a
difference the comparator found could be "the sample file disagrees
with the database" rather than "the two implementations disagree".
Same discipline as generator/generate_flatfile.py, different target
representation.

The output is committed to edi/samples/ so the workshop does not
depend on this script running. Regenerate with:

    python3 edi/generate_samples.py

CHARACTER SET
-------------
UNB declares UNOA, which is upper-case only and excludes the EDIFACT
service characters + : ' ? and *. Descriptions are folded accordingly.
That is not POC laziness - it is why partner descriptions arrive
shouting and truncated, and it is one source of the MATERIAL
differences the comparator reports.
"""

import os
import re
import sys
from datetime import datetime

import psycopg2

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "samples")

# Fixed so regenerating does not churn the committed files.
STAMP = datetime(2026, 8, 18, 10, 30)

SENDER = "DFTZ001"
RECIPIENT = "JKDM"

# UN/EDIFACT 1001 document name code 929 = "Customs declaration".
DOC_CODE = "929"

UOM_BY_HS = {}


def unoa(text):
    """Fold text to the UNOA character set: upper case, service
    characters and anything else outside the repertoire removed."""
    if text is None:
        return ""
    out = str(text).upper()
    out = out.replace("'", " ").replace("+", " ").replace(":", " ")
    out = out.replace("?", " ").replace("*", " ")
    out = re.sub(r"[^A-Z0-9 .,\-()/=%]", " ", out)
    return re.sub(r"\s+", " ", out).strip()


def build_cusdec(decl, lines, control_ref):
    """One interchange containing one CUSDEC message."""
    (decl_ref, decl_type, declarant_tin, origin, fta, local_pct,
     currency) = decl

    segs = []
    segs.append(
        f"UNB+UNOA:2+{SENDER}:ZZ+{RECIPIENT}:ZZ+"
        f"{STAMP:%y%m%d}:{STAMP:%H%M}+{control_ref}"
    )
    segs.append(f"UNH+{control_ref}+CUSDEC:D:96A:UN")
    segs.append(f"BGM+{DOC_CODE}+{decl_ref}+9")
    segs.append(f"DTM+137:{STAMP:%Y%m%d%H%M}:203")
    segs.append(f"NAD+DT+{declarant_tin}::91")

    # ALI carries country of origin and the preference claimed.
    if fta:
        segs.append(f"ALI+{origin}+++{fta}")
        if local_pct is not None:
            segs.append(f"PCD+12:{local_pct:.2f}")
    else:
        segs.append(f"ALI+{origin}")

    segs.append(f"CUX+2:{currency}:4")
    segs.append("LOC+16+PKG:139:6")
    segs.append("TDT+20++1")

    for line_no, hs_code, description, quantity, customs_value, uom in lines:
        segs.append(f"LIN+{line_no}++{hs_code}:HS")
        segs.append(f"IMD+F++:::{unoa(description)}")
        segs.append(f"QTY+47:{quantity:g}:{uom}")
        segs.append(f"MOA+38:{customs_value:.2f}")

    # UNT counts every segment from UNH to UNT inclusive.
    body_count = len(segs) - 1 + 1
    segs.append(f"UNT+{body_count}+{control_ref}")
    segs.append(f"UNZ+1+{control_ref}")

    return "'\n".join(segs) + "'\n"


DECL_QUERY = """
SELECT decl_ref, decl_type, declarant_tin, origin_country,
       COALESCE(fta_claimed, ''), local_pct, currency_code
  FROM declaration
 ORDER BY decl_ref
"""

LINE_QUERY = """
SELECT l.line_no, l.hs_code, t.description, l.quantity,
       l.customs_value, t.uom
  FROM declaration_line l
  JOIN tariff_rate t ON t.hs_code = l.hs_code
 WHERE l.decl_ref = %s
 ORDER BY l.line_no
"""


def main():
    conn = psycopg2.connect(
        host=os.environ.get("PG_HOST", "localhost"),
        port=os.environ.get("PG_PORT", "5432"),
        user=os.environ.get("PG_USER", "jkdm"),
        password=os.environ.get("PG_PASSWORD", "jkdm_poc"),
        dbname=os.environ.get("PG_DB", "smk"),
    )

    os.makedirs(OUT_DIR, exist_ok=True)

    written = []
    with conn.cursor() as cur:
        cur.execute(DECL_QUERY)
        declarations = cur.fetchall()

        for seq, decl in enumerate(declarations, start=1):
            decl_ref = decl[0]
            with conn.cursor() as lcur:
                lcur.execute(LINE_QUERY, (decl_ref,))
                lines = lcur.fetchall()

            if not lines:
                continue

            control_ref = f"{seq:09d}"
            content = build_cusdec(decl, lines, control_ref)
            name = f"CUSDEC_{decl_ref}.edi"
            with open(os.path.join(OUT_DIR, name), "w", encoding="ascii") as fh:
                fh.write(content)
            written.append(name)

    conn.close()

    # ---- negative cases -------------------------------------------
    # Two DIFFERENT failures. Attendees should see that "rejected" is
    # not one outcome: a syntax failure is the partner's software
    # problem, a business failure is the broker's data problem, and
    # they go to different people to fix.

    # 1. Truncated interchange - the UNT/UNZ trailers never arrive.
    malformed = (
        "UNB+UNOA:2+DFTZ001:ZZ+JKDM:ZZ+260818:1030+000000901'\n"
        "UNH+000000901+CUSDEC:D:96A:UN'\n"
        "BGM+929+K1-2026-000901+9'\n"
        "DTM+137:202608181030:203'\n"
        "NAD+DT+C12345678909::91'\n"
        "LIN+1++8471.30.10:HS'\n"
        "MOA+38:15000.0\n"
    )
    with open(os.path.join(OUT_DIR, "CUSDEC_MALFORMED.edi"), "w") as fh:
        fh.write(malformed)
    written.append("CUSDEC_MALFORMED.edi")

    # 2. Structurally perfect and it parses cleanly, but the core
    #    holds no such declaration reference (and the HS code is not
    #    in the tariff table either). A BUSINESS rejection, not a
    #    syntax one - and the partner gets told so.
    unknown_hs = (
        "UNB+UNOA:2+DFTZ001:ZZ+JKDM:ZZ+260818:1030+000000902'\n"
        "UNH+000000902+CUSDEC:D:96A:UN'\n"
        "BGM+929+K1-2026-000902+9'\n"
        "DTM+137:202608181030:203'\n"
        "NAD+DT+C12345678910::91'\n"
        "ALI+CN'\n"
        "CUX+2:MYR:4'\n"
        "LOC+16+PKG:139:6'\n"
        "TDT+20++1'\n"
        "LIN+1++9999.99.99:HS'\n"
        "IMD+F++:::COMMODITY NOT IN THE TARIFF TABLE'\n"
        "QTY+47:5:UNT'\n"
        "MOA+38:7500.00'\n"
        "UNT+12+000000902'\n"
        "UNZ+1+000000902'\n"
    )
    with open(os.path.join(OUT_DIR, "CUSDEC_UNPRICEABLE.edi"), "w") as fh:
        fh.write(unknown_hs)
    written.append("CUSDEC_UNPRICEABLE.edi")

    # 3. A CUSCAR manifest. Deliberately NOT wired up - this is the
    #    hands-on exercise. Today the intake process rejects it with
    #    "unsupported message type", which is the correct starting
    #    point for the attendees.
    # 3. A CUSCAR manifest, deliberately describing MANIFEST-2026-0041 -
    #    a manifest that exists in the database. Stage 1 of the exercise
    #    ingests this file; stage 2 compares the same manifest through
    #    the router, so the two halves join up.
    cuscar = (
        "UNB+UNOA:2+DFTZ001:ZZ+JKDM:ZZ+260818:1030+000000903'\n"
        "UNH+000000903+CUSCAR:D:96A:UN'\n"
        "BGM+85+MANIFEST-2026-0041+9'\n"
        "DTM+137:202608181030:203'\n"
        "NAD+CA+C99000000001::91'\n"
        "TDT+20+VOY-8841+1++CARRIER:172:20++++9V-8841:103:11:MV BINTANG SATU'\n"
        "LOC+11+MYPKG:139:6'\n"
        "DTM+132:202608200600:203'\n"
        "CNI+1+CN-88410001'\n"
        "GID+1+120:CT'\n"
        "FTX+AAA+++CONSOLIDATED ELECTRONICS'\n"
        "MEA+AAE+G+KGM:2400'\n"
        "UNT+12+000000903'\n"
        "UNZ+1+000000903'\n"
    )
    with open(os.path.join(OUT_DIR, "CUSCAR_MANIFEST.edi"), "w") as fh:
        fh.write(cuscar)
    written.append("CUSCAR_MANIFEST.edi")

    print(f"[edi] wrote {len(written)} files to {OUT_DIR}")
    for name in written:
        print(f"       {name}")

    if not written:
        print("[edi] ERROR: nothing written", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
