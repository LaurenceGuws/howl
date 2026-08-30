#!/usr/bin/env python3
"""Prove invisible interaction modes are observable before they change CLI input."""

from __future__ import annotations

import json
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def timeout(_signum, _frame):
    raise TimeoutError("CLI interaction observability proof exceeded 20 seconds")


def require(condition: bool, message: object) -> None:
    if not condition:
        raise AssertionError(message)


def run_json(cli: Path, *args: str, input_bytes: bytes | None = None) -> dict:
    completed = subprocess.run([str(cli), *args], input=input_bytes, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"CLI failed rc={completed.returncode} args={args!r}: {completed.stderr.decode(errors='replace')}")
    value = json.loads(completed.stdout.decode())
    require(isinstance(value, dict), value)
    return value


def snapshot(cli: Path, endpoint: str) -> dict:
    value = run_json(cli, "snapshot", endpoint)
    require(value.get("schema") == "howl.snapshot/v1", value)
    return value


def state(cli: Path, endpoint: str) -> dict:
    value = run_json(cli, "state", endpoint)
    require(value.get("schema") == "howl.state/v1", value)
    return value


def visible_text(value: dict) -> str:
    return "\n".join(value["lines"])


def until_text(cli: Path, endpoint: str, needle: str) -> dict:
    seen = ""
    for _ in range(80):
        value = snapshot(cli, endpoint)
        seen = visible_text(value)
        if needle in seen:
            return value
        time.sleep(0.01)
    raise AssertionError(f"missing terminal text {needle!r}: {seen!r}")


def normalized_visible(value: dict) -> dict:
    return {key: item for key, item in value.items() if key not in {"revision", "terminal_revision"}}


def start_server(sessiond: Path, socket: Path, command: str) -> subprocess.Popen:
    return subprocess.Popen([str(sessiond), str(socket), "/bin/sh", "8", "64", command], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def wait_socket(server: subprocess.Popen, socket: Path) -> None:
    deadline = time.monotonic() + 2
    while not socket.exists():
        if server.poll() is not None:
            stderr = server.stderr.read() if server.stderr else ""
            raise RuntimeError(f"sessiond exited before socket publication: {stderr}")
        if time.monotonic() >= deadline:
            raise TimeoutError("session socket did not appear")
        time.sleep(0.01)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: interaction_observability.py HOWL HOWL_SESSIOND")
    cli = Path(sys.argv[1]).resolve()
    sessiond = Path(sys.argv[2]).resolve()
    signal.signal(signal.SIGALRM, timeout)
    signal.alarm(20)

    plain_command = (
        "stty -echo -icanon min 1 time 0; printf 'READY'; "
        "bytes=$(dd bs=1 count=3 2>/dev/null | od -An -tx1 -v | tr -d '[:space:]'); "
        "printf '\\rRESULT:%s\\n' \"$bytes\"; cat"
    )
    bracketed_command = (
        "stty -echo -icanon min 1 time 0; printf 'READY'; printf '\\033[?2004h'; "
        "bytes=$(dd bs=1 count=15 2>/dev/null | od -An -tx1 -v | tr -d '[:space:]'); "
        "printf '\\rRESULT:%s\\n' \"$bytes\"; cat"
    )

    with tempfile.TemporaryDirectory(prefix="howl-cli-modes-") as root_text:
        root = Path(root_text)
        sockets = [root / "plain.sock", root / "bracketed.sock"]
        servers = [start_server(sessiond, sockets[0], plain_command), start_server(sessiond, sockets[1], bracketed_command)]
        try:
            for server, socket in zip(servers, sockets, strict=True):
                wait_socket(server, socket)
            endpoints = [f"unix:{socket}" for socket in sockets]
            snapshots = [until_text(cli, endpoint, "READY") for endpoint in endpoints]
            require(
                normalized_visible(snapshots[0]) == normalized_visible(snapshots[1]),
                "compact visible semantic snapshots should collide before interaction-state observation",
            )

            states = [state(cli, endpoint) for endpoint in endpoints]
            require(states[0]["bracketed_paste"] is False, states[0])
            require(states[1]["bracketed_paste"] is True, states[1])
            require(states[0]["terminal_revision"] >= snapshots[0]["terminal_revision"], states[0])
            require(states[1]["terminal_revision"] >= snapshots[1]["terminal_revision"], states[1])

            for endpoint in endpoints:
                result = run_json(cli, "paste", endpoint, "--stdin", input_bytes=b"x\x00y")
                require(result == {"schema": "howl.action/v1", "operation": "paste", "result": "ok"}, result)

            plain = until_text(cli, endpoints[0], "RESULT:780079")
            bracketed = until_text(cli, endpoints[1], "RESULT:1b5b3230307e7800791b5b3230317e")
            require("RESULT:780079" in visible_text(plain), "plain paste bytes")
            require("RESULT:1b5b3230307e7800791b5b3230317e" in visible_text(bracketed), "bracketed paste bytes")
            print("Howl CLI interaction observability: PASS")
        finally:
            signal.alarm(0)
            for server in servers:
                server.terminate()
                try:
                    server.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    server.kill(); server.wait()


if __name__ == "__main__":
    main()
