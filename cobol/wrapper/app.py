"""
JKDM SMK POC - thin HTTP wrapper over the COBOL binary.

DEMO TALKING POINT
------------------
This wrapper shells out to the compiled COBOL program per request.
That is ONE of the four unresolved options for how IRIS invokes
Visual COBOL in production (spec 5.3):

  1. thin service wrapper shelling out      <- what this does
  2. COBOL exposes native TCP/REST services
  3. IRIS native gateway call
  4. batch file handoff

It is chosen here for POC convenience, NOT as a recommendation.
Say that out loud during the demo - the mock's own integration
approach is a live example of the open architecture question.

The response is returned as the RAW fixed-width payload. Parsing it
is IRIS's job, which is the point: if this returned clean JSON the
fabric would have nothing to do.
"""

import os
import random
import subprocess
import time

from flask import Flask, jsonify, request

app = Flask(__name__)

COBOL_BIN = os.environ.get("COBOL_BIN", "/opt/cobol/bin/DUTYCALC")
MANIFEST_BIN = os.environ.get("MANIFEST_BIN", "/opt/cobol/bin/MANIFEST")
DATA_DIR = os.environ.get("COBOL_DATA_DIR", "/data")
LAT_MIN = int(os.environ.get("LATENCY_MS_MIN", "200"))
LAT_MAX = int(os.environ.get("LATENCY_MS_MAX", "400"))

# Deterministic latency jitter - seeded so demo runs are reproducible.
_rng = random.Random(20260819)


@app.route("/health")
def health():
    ok = (
        os.path.exists(COBOL_BIN)
        and os.path.exists(MANIFEST_BIN)
        and os.path.exists(os.path.join(DATA_DIR, "declline.dat"))
        and os.path.exists(os.path.join(DATA_DIR, "manifest.dat"))
    )
    return (jsonify({"status": "UP" if ok else "DOWN"}), 200 if ok else 503)


@app.route("/duty/calculate", methods=["POST"])
def calculate():
    """
    Request:  {"declarationRef": "K1-2026-000104"}
    Response: {"raw": "<fixed-width header>", "lines": ["<fixed-width>", ...]}

    Deliberately mainframe-era: positional, zero-padded, no ISO
    timestamps, PIC X(35) truncated descriptions.
    """
    payload = request.get_json(silent=True) or {}
    decl_ref = (payload.get("declarationRef") or "").strip()

    if not decl_ref:
        return jsonify({"error": "declarationRef required"}), 400

    # Mainframe-era latency. Makes the case for async shadow dispatch
    # concrete rather than theoretical.
    time.sleep(_rng.randint(LAT_MIN, LAT_MAX) / 1000.0)

    env = dict(os.environ, COBOL_DATA_DIR=DATA_DIR)

    try:
        proc = subprocess.run(
            [COBOL_BIN, decl_ref],
            capture_output=True,
            text=True,
            timeout=15,
            env=env,
        )
    except subprocess.TimeoutExpired:
        return jsonify({"error": "COBOL timeout"}), 504

    if proc.returncode != 0:
        return jsonify({"error": "COBOL abend", "detail": proc.stderr}), 500

    out = [ln.rstrip("\n") for ln in proc.stdout.splitlines() if ln.strip()]
    lines = [ln for ln in out if ln.startswith("LN")]
    header = next((ln for ln in out if ln.startswith(("OK", "ER"))), "")

    if header.startswith("ER"):
        return jsonify({"error": "declaration not found", "raw": header}), 404

    return jsonify({"raw": header, "lines": lines, "backend": "COBOL"})


@app.route("/manifest/<manifest_ref>", methods=["GET"])
def manifest(manifest_ref):
    """
    Response: {"raw": "<fixed-width header>", "lines": [...]}

    Same shape as the duty calculation: positional, space padded,
    YYYYMMDDHHMMSS timestamps with no zone. IRIS normalises it.

    Note the program COUNTS consignment records. The PHP service reads
    a denormalised counter column. Where that counter has drifted the
    two disagree - which is the exercise.
    """
    ref = (manifest_ref or "").strip()
    if not ref:
        return jsonify({"error": "manifest reference required"}), 400

    time.sleep(_rng.randint(LAT_MIN, LAT_MAX) / 1000.0)

    env = dict(os.environ, COBOL_DATA_DIR=DATA_DIR)
    try:
        proc = subprocess.run(
            [MANIFEST_BIN, ref],
            capture_output=True, text=True, timeout=15, env=env,
        )
    except subprocess.TimeoutExpired:
        return jsonify({"error": "COBOL timeout"}), 504

    if proc.returncode != 0:
        return jsonify({"error": "COBOL abend", "detail": proc.stderr}), 500

    out = [ln.rstrip("\n") for ln in proc.stdout.splitlines() if ln.strip()]
    lines = [ln for ln in out if ln.startswith("LN")]
    header = next((ln for ln in out if ln.startswith(("OK", "ER"))), "")

    if header.startswith("ER"):
        return jsonify({"error": "manifest not found", "raw": header}), 404

    return jsonify({"raw": header, "lines": lines, "backend": "COBOL"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
