#!/usr/bin/env python3
"""Black-box proof that the native CLI composes canonical Howl session state."""

from __future__ import annotations

import json
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def fail_timeout(_signum, _frame):
    raise TimeoutError("Howl CLI composition proof exceeded 30 seconds")


def require(condition: bool, message: object) -> None:
    if not condition:
        raise AssertionError(message)


def run_json(cli: Path, *args: str, input_bytes: bytes | None = None) -> dict:
    completed = subprocess.run(
        [str(cli), *args],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"CLI failed rc={completed.returncode} args={args!r}: "
            f"{completed.stderr.decode(errors='replace')}"
        )
    value = json.loads(completed.stdout.decode())
    require(isinstance(value, dict), value)
    return value


def snapshot(cli: Path, endpoint: str) -> dict:
    value = run_json(cli, "snapshot", endpoint)
    require(value.get("schema") == "howl.snapshot/v1", value)
    return value


def visible_text(value: dict) -> str:
    return "\n".join(value["lines"])


def wait_text(cli: Path, endpoint: str, needle: str) -> dict:
    seen = ""
    for _ in range(80):
        value = snapshot(cli, endpoint)
        seen = visible_text(value)
        if needle in seen:
            return value
        time.sleep(0.01)
    raise AssertionError(f"did not observe {needle!r}: {seen!r}")


def action(cli: Path, endpoint: str, operation: str, *args: str, input_bytes: bytes | None = None) -> None:
    value = run_json(cli, operation, endpoint, *args, input_bytes=input_bytes)
    require(
        value == {"schema": "howl.action/v1", "operation": operation, "result": "ok"},
        value,
    )


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: composition.py HOWL HOWL_SESSIOND")
    cli = Path(sys.argv[1]).resolve()
    sessiond = Path(sys.argv[2]).resolve()
    signal.signal(signal.SIGALRM, fail_timeout)
    signal.alarm(30)

    command = (
        "stty -echo -icanon min 1 time 0; "
        "capture() { printf '%s:' \"$1\"; "
        "dd bs=1 count=\"$2\" 2>/dev/null | od -An -tx1 -v | tr -d '[:space:]'; "
        "printf '\\n'; }; "
        "printf 'NORMAL\\n'; capture normal 3; "
        "printf '\\033[?1hAPP_CURSOR\\n'; capture app_cursor 3; "
        "printf '\\033[?2004hPASTE\\n'; capture paste 15; "
        "printf 'DONE\\n'; cat"
    )

    with tempfile.TemporaryDirectory(prefix="howl-cli-") as temporary:
        socket = Path(temporary) / "session.sock"
        server = subprocess.Popen(
            [str(sessiond), str(socket), "/bin/sh", "12", "72", command],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        try:
            deadline = time.monotonic() + 2
            while not socket.exists():
                if server.poll() is not None:
                    stderr = server.stderr.read().decode(errors="replace") if server.stderr else ""
                    raise RuntimeError(f"sessiond exited before socket publication: {stderr}")
                if time.monotonic() >= deadline:
                    raise TimeoutError("session socket did not appear")
                time.sleep(0.01)

            endpoint = f"unix:{socket}"
            initial = wait_text(cli, endpoint, "NORMAL")
            require(initial["geometry"] == {"rows": 12, "columns": 72}, initial)
            require(initial["resize"] == {"leader_present": False, "you_are_leader": False}, initial)

            state = run_json(cli, "state", endpoint)
            require(state["schema"] == "howl.state/v1", state)
            require(state["application_cursor_keys"] is False, state)
            require(state["bracketed_paste"] is False, state)
            after_state = snapshot(cli, endpoint)
            require(after_state["geometry"] == initial["geometry"], after_state)
            require(after_state["resize"] == initial["resize"], after_state)

            action(cli, endpoint, "key", "up")
            app = wait_text(cli, endpoint, "APP_CURSOR")
            require("normal:1b5b41" in visible_text(app), visible_text(app))
            state = run_json(cli, "state", endpoint)
            require(state["application_cursor_keys"] is True, state)

            action(cli, endpoint, "key", "up")
            paste_stage = wait_text(cli, endpoint, "PASTE")
            require("app_cursor:1b4f41" in visible_text(paste_stage), visible_text(paste_stage))
            state = run_json(cli, "state", endpoint)
            require(state["bracketed_paste"] is True, state)

            action(cli, endpoint, "paste", "--stdin", input_bytes=b"x\x00y")
            done = wait_text(cli, endpoint, "DONE")
            require(
                "paste:1b5b3230307e7800791b5b3230317e" in visible_text(done),
                visible_text(done),
            )

            action(cli, endpoint, "resize", "7", "20")
            resized = snapshot(cli, endpoint)
            require(resized["geometry"] == {"rows": 7, "columns": 20}, resized)
            require(resized["resize"] == {"leader_present": False, "you_are_leader": False}, resized)

            action(cli, endpoint, "type", "TYPE_OK")
            require("TYPE_OK" in visible_text(wait_text(cli, endpoint, "TYPE_OK")), "type after reconnect")
            require(server.poll() is None, "CLI disconnect terminated canonical session")
        finally:
            server.terminate()
            try:
                server.wait(timeout=2)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=2)

    signal.alarm(0)
    print("Howl CLI composition: PASS")


if __name__ == "__main__":
    main()
