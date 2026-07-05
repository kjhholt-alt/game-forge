r"""Run ck3-tiger against a CK3 mod and gate on fatal/error findings.

ck3-tiger's own exit code is always 0 regardless of what it finds (confirmed
2026-07-05 against a deliberately broken test mod) -- it is a reporter, not a
gate. This script is the gate: it parses --json output and exits non-zero
when any fatal/error severity report exists.

Usage:
    py validate.py                     # checks the default saga_engine mod
    py validate.py path\to\Other.mod   # checks a specific mod

Env overrides:
    CK3_TIGER_EXE   path to ck3-tiger.exe (default: ~/.operator/bin/ck3-tiger)
    CK3_GAME_DIR    path to the CK3 install ROOT, not the game\\ subfolder
                    (default: A:\\Steam\\steamapps\\common\\Crusader Kings III)
"""
import json
import os
import subprocess
import sys

TIGER_EXE = os.environ.get(
    "CK3_TIGER_EXE",
    r"C:\Users\Kruz\.operator\bin\ck3-tiger\ck3-tiger.exe",
)
GAME_DIR = os.environ.get(
    "CK3_GAME_DIR",
    r"A:\Steam\steamapps\common\Crusader Kings III",
)
DEFAULT_MOD = (
    r"C:\Users\Kruz\Documents\Paradox Interactive\Crusader Kings III"
    r"\mod\saga_engine.mod"
)

GATE_SEVERITIES = {"fatal", "error"}


def run(mod_path: str) -> int:
    if not os.path.isfile(TIGER_EXE):
        print(f"validate.py: ck3-tiger.exe not found at {TIGER_EXE}", file=sys.stderr)
        return 2
    if not os.path.isfile(mod_path):
        print(f"validate.py: mod file not found at {mod_path}", file=sys.stderr)
        return 2

    proc = subprocess.run(
        [TIGER_EXE, "--json", "--game", GAME_DIR, mod_path],
        capture_output=True,
        text=True,
    )

    try:
        reports = json.loads(proc.stdout)
    except json.JSONDecodeError:
        print(proc.stdout)
        print(proc.stderr, file=sys.stderr)
        print("validate.py: could not parse ck3-tiger JSON output", file=sys.stderr)
        return 2

    by_severity = {}
    for r in reports:
        sev = r.get("severity", "unknown")
        by_severity[sev] = by_severity.get(sev, 0) + 1

    if reports:
        summary = ", ".join(f"{k}:{v}" for k, v in sorted(by_severity.items()))
    else:
        summary = "no problems found"
    print(f"ck3-tiger: {len(reports)} report(s) -- {summary}")

    gate_hits = [r for r in reports if r.get("severity") in GATE_SEVERITIES]
    if gate_hits:
        print(f"\n{len(gate_hits)} gate-blocking issue(s) (fatal/error):", file=sys.stderr)
        for r in gate_hits:
            loc = (r.get("locations") or [{}])[0]
            where = f"{loc.get('path')}:{loc.get('linenr')}"
            print(f"  [{r.get('severity')}] {r.get('key')} @ {where} -- {r.get('message')}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    mod_arg = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_MOD
    sys.exit(run(mod_arg))
