"""run-tests.py -- run pytest for game-forge and emit status.

Drop-in test wrapper: forwards args to pytest, captures pass/fail counts,
then calls scripts/emit-status.py with the result. Fail-closed-safe:
emitter never blocks the test exit code.

Usage:
    py scripts/run-tests.py [pytest args...]
"""
from __future__ import annotations

import re
import subprocess
import sys
import time
from pathlib import Path


def main() -> int:
    here = Path(__file__).resolve().parent
    repo_root = here.parent
    pytest_target = repo_root / "tests"
    if not pytest_target.exists():
        pytest_target = repo_root

    extra = sys.argv[1:]
    # By default, skip the bridge E2E tests -- they require a running Godot
    # instance with the agent harness loaded. Caller can re-enable with
    # `--with-e2e` to opt back in.
    deselect: list[str] = []
    if "--with-e2e" in extra:
        extra = [a for a in extra if a != "--with-e2e"]
    else:
        deselect = ["--ignore", str(repo_root / "tests" / "test_bridge_e2e.py")]

    # -ra forces a short summary even when project pyproject sets -q.
    cmd = [sys.executable, "-m", "pytest", str(pytest_target),
           "--tb=short", "-ra", "-o", "addopts="] + deselect + extra
    print(f"[run-tests] {' '.join(cmd)}", flush=True)

    t0 = time.time()
    proc = subprocess.run(cmd, cwd=str(repo_root), capture_output=True, text=True)
    duration = int(time.time() - t0)

    out = proc.stdout + "\n" + proc.stderr
    sys.stdout.write(proc.stdout)
    sys.stderr.write(proc.stderr)

    # Parse "X passed", "X failed" from pytest tail.
    passed = -1
    failed = 0
    m = re.search(r"(\d+)\s+passed", out)
    if m:
        passed = int(m.group(1))
    m = re.search(r"(\d+)\s+failed", out)
    if m:
        failed = int(m.group(1))

    # Decide health.
    exit_code = proc.returncode
    if exit_code == 0:
        health = "green"
    elif failed > 0:
        health = "red"
    else:
        health = "yellow"

    summary = (
        f"all {passed} tests passing ({duration}s)"
        if health == "green" and passed >= 0
        else f"tests exit={exit_code} passed={passed} failed={failed}"
    )

    emit = here / "emit-status.py"
    if emit.exists():
        emit_args = [
            sys.executable, str(emit),
            "--health", health,
            "--summary", summary,
            "--tests-passed", str(max(passed, 0)),
            "--tests-failed", str(failed),
            "--duration-sec", str(duration),
            "--exit-code", str(exit_code),
        ]
        try:
            subprocess.run(emit_args, check=False, timeout=30)
        except Exception as exc:
            print(f"[run-tests] emit-status non-fatal: {exc}", file=sys.stderr)

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
