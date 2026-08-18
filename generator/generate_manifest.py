"""
JKDM SMK POC - Postgres -> COBOL fixed-width manifest file.

Companion to generate_flatfile.py, same reasoning: both backends read
the same underlying data, so any difference the comparator finds is
implementation, not data divergence.

The record is denormalised - manifest header fields repeat on every
consignment row - because that is what a flat file handed to a COBOL
program actually looks like.
"""

import os
import sys

import psycopg2

OUT_DIR = os.environ.get("OUT_DIR", "/data")
OUT_FILE = os.path.join(OUT_DIR, "manifest.dat")

RECORD_LEN = 207


def num(value, total_digits, decimals):
    if value is None:
        value = 0
    scaled = int(round(float(value) * (10 ** decimals)))
    if scaled < 0:
        scaled = 0
    return str(scaled).rjust(total_digits, "0")[-total_digits:]


def alpha(value, width):
    """Left-justified, space-padded, truncated - PIC X(n).

    The padding is not cosmetic. It survives into the COBOL response
    and shows up in the comparator, which is the point.
    """
    if value is None:
        value = ""
    return str(value)[:width].ljust(width)


QUERY = """
SELECT m.manifest_ref, m.vessel_id, m.vessel_name, m.voyage_no,
       m.carrier_tin, m.port_of_discharge,
       to_char(m.eta AT TIME ZONE 'Asia/Kuala_Lumpur', 'YYYYMMDDHH24MISS'),
       m.status_code,
       c.line_no, c.consignment_ref, c.container_count, c.gross_kg,
       c.description
  FROM manifest m
  JOIN manifest_consignment c ON c.manifest_ref = m.manifest_ref
 ORDER BY m.manifest_ref, c.line_no
"""


def build_record(row):
    (ref, vessel_id, vessel_name, voyage, carrier, port, eta, status,
     line_no, cons_ref, containers, gross, desc) = row

    rec = (
        alpha(ref, 24)
        + alpha(vessel_id, 16)
        + alpha(vessel_name, 30)      # <-- PIC X(30), padded
        + alpha(voyage, 12)
        + alpha(carrier, 16)
        + alpha(port, 8)
        + alpha(eta, 14)              # <-- local time, no zone carried
        + alpha(status, 2)
        + num(line_no, 3, 0)
        + alpha(cons_ref, 24)
        + num(containers, 5, 0)
        + num(gross, 13, 2)
        + alpha(desc, 40)             # <-- PIC X(40) truncation
    )
    assert len(rec) == RECORD_LEN, f"record length {len(rec)} != {RECORD_LEN}"
    return rec


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

    print(f"[generator] wrote {count} manifest records to {OUT_FILE}")
    if count == 0:
        print("[generator] ERROR: no manifest records", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
