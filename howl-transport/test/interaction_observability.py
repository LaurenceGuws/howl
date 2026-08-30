#!/usr/bin/env python3
"""Prove invisible interaction modes are observable before they change input."""

from __future__ import annotations

import json
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def timeout(_signum, _frame):
    raise TimeoutError("interaction observability proof exceeded 20 seconds")


def require(condition: bool, message: object) -> None:
    if not condition:
        raise AssertionError(message)


class Transport:
    def __init__(self, executable: Path, socket: Path):
        self.process = subprocess.Popen(
            [str(executable), "stream", f"unix:{socket}"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        require(self.process.stdin is not None and self.process.stdout is not None, "missing pipes")
        welcome = self.read()
        require(welcome.get("record") == "welcome" and welcome.get("features") == 63, welcome)

    def close(self) -> None:
        if self.process.stdin:
            self.process.stdin.close()
        self.process.terminate()
        try:
            self.process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()

    def read(self) -> dict:
        raw = self.process.stdout.readline()
        if not raw:
            stderr = self.process.stderr.read() if self.process.stderr else ""
            raise RuntimeError(f"transport closed early: {stderr}")
        value = json.loads(raw)
        require(isinstance(value, dict), value)
        return value

    def send(self, value: dict) -> None:
        self.process.stdin.write(json.dumps(value, separators=(",", ":")) + "\n")
        self.process.stdin.flush()

    def interaction(self) -> dict:
        self.send({"request": "interaction_state"})
        value = self.read()
        require(value.get("record") == "interaction_state", value)
        return value

    def snapshot(self, after: int = 0) -> tuple[dict, list[dict]]:
        self.send({"request": "observe", "after_revision": after, "history_offset": 0})
        records = []
        while True:
            value = self.read()
            records.append(value)
            if value.get("record") == "snapshot_end":
                break
        require(records[0].get("record") == "snapshot_begin", records[0])
        return records[0], records

    def until_text(self, needle: str, revision: int = 0) -> tuple[dict, list[dict]]:
        for _ in range(20):
            begin, records = self.snapshot(revision)
            revision = begin["revision"]
            if needle in visible_text(records):
                return begin, records
        raise AssertionError(f"missing terminal text: {needle}")

    def paste(self) -> None:
        self.send({"request": "paste", "bytes_hex": "780079"})
        require(
            self.read() == {"record": "result", "request_kind": "input", "code": "ok"},
            "paste result",
        )


def visible_text(records: list[dict]) -> str:
    lines = []
    for record in records:
        if record.get("record") != "row":
            continue
        line = []
        for cell in record["cells"]:
            if cell["scalars"] and cell["x"] == 0 and cell["y"] == 0:
                line.extend(chr(scalar) for scalar in cell["scalars"])
            elif cell["width"] == 1 and cell["height"] == 1:
                line.append(" ")
        lines.append("".join(line))
    return "\n".join(lines)


def visible_semantics(records: list[dict]) -> list[dict]:
    """Remove only time/revision identity; retain every transported presentation/cell fact."""
    result = []
    for record in records:
        kind = record.get("record")
        if kind == "snapshot_begin":
            result.append({
                key: value
                for key, value in record.items()
                if key not in {"revision", "terminal_revision"}
            })
        elif kind == "snapshot_end":
            result.append({"record": "snapshot_end"})
        elif kind == "presentation":
            copy = dict(record)
            copy["cursor_age_ns"] = None
            result.append(copy)
        else:
            result.append(record)
    return result


def start_server(sessiond: Path, socket: Path, command: str) -> subprocess.Popen:
    return subprocess.Popen(
        [str(sessiond), str(socket), "/bin/sh", "8", "64", command],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


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
        raise SystemExit("usage: interaction_observability.py HOWL_TRANSPORT HOWL_SESSIOND")
    transport_exe = Path(sys.argv[1]).resolve()
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

    with tempfile.TemporaryDirectory(prefix="howl-ax-modes-") as root:
        root = Path(root)
        sockets = [root / "plain.sock", root / "bracketed.sock"]
        servers = [
            start_server(sessiond, sockets[0], plain_command),
            start_server(sessiond, sockets[1], bracketed_command),
        ]
        transports: list[Transport] = []
        try:
            for server, socket in zip(servers, sockets, strict=True):
                wait_socket(server, socket)
                transports.append(Transport(transport_exe, socket))

            snapshots = [transport.until_text("READY") for transport in transports]
            require(
                visible_semantics(snapshots[0][1]) == visible_semantics(snapshots[1][1]),
                "visible semantic snapshots should collide before interaction-state observation",
            )

            states = [transport.interaction() for transport in transports]
            require(states[0]["bracketed_paste"] is False, states[0])
            require(states[1]["bracketed_paste"] is True, states[1])
            require(states[0]["terminal_revision"] >= snapshots[0][0]["terminal_revision"], states[0])
            require(states[1]["terminal_revision"] >= snapshots[1][0]["terminal_revision"], states[1])

            for transport in transports:
                transport.paste()
            plain = transports[0].until_text("RESULT:780079")[1]
            bracketed = transports[1].until_text("RESULT:1b5b3230307e7800791b5b3230317e")[1]
            require("RESULT:780079" in visible_text(plain), "plain paste bytes")
            require(
                "RESULT:1b5b3230307e7800791b5b3230317e" in visible_text(bracketed),
                "bracketed paste bytes",
            )
            print("AX interaction observability: PASS")
        finally:
            signal.alarm(0)
            for transport in transports:
                transport.close()
            for server in servers:
                server.terminate()
                try:
                    server.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait()


if __name__ == "__main__":
    main()
