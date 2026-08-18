"""
JKDM SMK POC - Postgres -> COBOL fixed-width flat file.

WHY THIS EXISTS
---------------
Both backends must read the SAME underlying data, or a difference the
comparator finds could be data divergence rather than logic - which
would destroy the point of the exercise.

Laravel reads Postgres directly via Eloquent. COBOL reads the flat
file this script derives from the same tables. Same data, two
representations.

This script IS the copybook-to-schema mapping made visible - the
CardDemo TS2-04 / TS3-04 decision ("the database schema becomes the
record-structure reference") as executable code. Open it during the
demo; it is more convincing than a slide about it.

NOTE: HS description is truncated to 35 chars here, matching
PIC X(35). Postgres holds VARCHAR(120). That truncation surfaces in
the comparator as a MATERIAL difference - genuine, not planted.
"""

import os
import sys

import psycopg2

OUT_DIR = os.environ.get("OUT_DIR", "/data")
OUT_FILE = os.path.join(OUT_DIR, "declline.dat")

RECORD_LEN = 159


def num(value, total_digits, decimals):
    """Zero-padded implied-decimal numeric, as COBOL PIC 9(n)V9(m)."""
    if value is None:
        value = 0
    scaled = int(round(float(value) * (10 ** decimals)))
    if scaled < 0:
        scaled = 0
    return str(scaled).rjust(total_digits, "0")[-total_digits:]


def alpha(value, width):
    """Left-justified, space-padded, truncated - as COBOL PIC X(n)."""
    if value is None:
        value = ""
    return str(value)[:width].ljust(width)


def build_record(row):
    (
        decl_ref, decl_type, declarant_tin, origin_country, fta_claimed,
        local_pct, currency_code, line_no, hs_code, description,
        quantity, customs_value, duty_rate, sst_rate,
        pref_rate, min_local_pct,
    ) = row

    has_pref = "Y" if pref_rate is not None else "N"

    rec = (
        alpha(decl_ref, 20)
        + alpha(decl_type, 4)
        + alpha(declarant_tin, 16)
        + alpha(origin_country, 2)
        + alpha(fta_claimed, 10)
        + num(local_pct, 5, 2)
        + alpha(currency_code, 3)
        + num(line_no, 3, 0)
        + alpha(hs_code, 10)
        + alpha(description, 35)          # <-- PIC X(35) truncation
        + num(quantity, 11, 3)
        + num(customs_value, 13, 2)
        + num(duty_rate, 7, 4)
        + num(sst_rate, 7, 4)
        + num(pref_rate, 7, 4)
        + num(min_local_pct, 5, 2)
        + has_pref
    )

    assert len(rec) == RECORD_LEN, f"record length {len(rec)} != {RECORD_LEN}"
    return rec


QUERY = """
SELECT d.decl_ref,
       d.decl_type,
       d.declarant_tin,
       d.origin_country,
       COALESCE(d.fta_claimed, ''),
       COALESCE(d.local_pct, 0),
       d.currency_code,
       l.line_no,
       l.hs_code,
       t.description,
       l.quantity,
       l.customs_value,
       t.duty_rate,
       t.sst_rate,
       f.pref_rate,
       COALESCE(f.min_local_pct, 0)
  FROM declaration       d
  JOIN declaration_line  l ON l.decl_ref = d.decl_ref
  JOIN tariff_rate       t ON t.hs_code  = l.hs_code
  LEFT JOIN fta_rule     f ON f.fta_code = d.fta_claimed
                          AND f.hs_code  = l.hs_code
                          AND f.origin_country = d.origin_country
 ORDER BY d.decl_ref, l.line_no
"""


def main():
    conn = psycopg2.connect(
        host=os.environ.get("PG_HOST", "postgres"),
        user=os.environ.get("PG_USER", "jkdm"),
        password=os.environ.get("PG_PASSWORD", "jkdm_poc"),
        dbname=os.environ.get("PG_DB", "smk"),
    )

    os.makedirs(OUT_DIR, exist_ok=True)

    count = 0
    with conn.cursor() as cur, open(OUT_FILE, "w", encoding="ascii") as fh:
        cur.execute(QUERY)
        for row in cur:
            fh.write(build_record(row) + "\n")
            count += 1

    conn.close()

    print(f"[generator] wrote {count} records to {OUT_FILE}")
    print(f"[generator] record length {RECORD_LEN}")

    if count == 0:
        print("[generator] ERROR: no records - check seed data", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
