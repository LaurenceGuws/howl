#!/usr/bin/env python3
"""Black-box proof that AX transport composes existing Howl state machines."""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def fail_timeout(_signum, _frame):
    raise TimeoutError("AX composition proof exceeded 30 seconds")


def require(condition: bool, message: object) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: composition.py HOWL_TRANSPORT HOWL_SESSIOND")
    transport_path = Path(sys.argv[1]).resolve()
    sessiond_path = Path(sys.argv[2]).resolve()
    signal.signal(signal.SIGALRM, fail_timeout)
    signal.alarm(30)

    command = (
        "stty -echo -icanon min 1 time 0; "
        "capture() { printf '%s:' \"$1\"; "
        "dd bs=1 count=\"$2\" 2>/dev/null | od -An -tx1 -v | tr -d '[:space:]'; "
        "printf '\\n'; }; "
        "printf 'NORMAL\\n'; capture normal 3; "
        "printf '\\033[?1hAPP_CURSOR\\n'; capture app_cursor 3; "
        "printf '\\033=APP_KEYPAD\\n'; capture app_keypad 3; "
        "printf '\\033[?1004hFOCUS\\n'; capture focus 3; "
        "printf '\\033[?1003h\\033[?1016hMOUSE\\n'; capture mouse 14; "
        "printf '\\033[?2004hPASTE\\n'; capture paste 15; "
        "printf '\\033[=31uKITTY_PRESS\\n'; capture kitty_press 5; "
        "printf 'KITTY_REPEAT\\n'; capture kitty_repeat 19; "
        "printf 'KITTY_RELEASE\\n'; capture kitty_release 9; "
        "printf 'DONE\\n'; cat"
    )

    with tempfile.TemporaryDirectory(prefix="howl-ax-") as temporary:
        socket_path = Path(temporary) / "session.sock"
        server = subprocess.Popen(
            [str(sessiond_path), str(socket_path), "/bin/sh", "24", "96", command],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        transport = None
        try:
            deadline = time.monotonic() + 2
            while not socket_path.exists():
                if server.poll() is not None:
                    stderr = server.stderr.read() if server.stderr else ""
                    raise RuntimeError(f"sessiond exited before socket publication: {stderr}")
                if time.monotonic() >= deadline:
                    raise TimeoutError("session socket did not appear")
                time.sleep(0.01)

            transport = subprocess.Popen(
                [str(transport_path), "stream", f"unix:{socket_path}"],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
            )
            require(transport.stdin is not None and transport.stdout is not None, "missing transport pipes")

            def read_record() -> dict:
                raw = transport.stdout.readline()
                if not raw:
                    stderr = transport.stderr.read() if transport.stderr else ""
                    raise RuntimeError(f"transport closed early: {stderr}")
                value = json.loads(raw)
                require(isinstance(value, dict), value)
                return value

            def send(value: dict) -> None:
                transport.stdin.write(json.dumps(value, separators=(",", ":")) + "\n")
                transport.stdin.flush()

            def expect_result(kind: str) -> None:
                require(
                    read_record() == {"record": "result", "request_kind": kind, "code": "ok"},
                    f"unexpected {kind} result",
                )

            def interaction_state() -> dict:
                send({"request": "interaction_state"})
                state = read_record()
                require(state.get("record") == "interaction_state", state)
                return state

            def snapshot(after_revision: int = 0) -> tuple[dict, str]:
                send({"request": "observe", "after_revision": after_revision, "history_offset": 0})
                records = []
                while True:
                    record = read_record()
                    records.append(record)
                    if record.get("record") == "snapshot_end":
                        break
                begin = records[0]
                require(begin.get("record") == "snapshot_begin", begin)
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
                    lines.append("".join(line).rstrip())
                return begin, "\n".join(lines)

            def observe_until(needle: str, revision: int) -> tuple[dict, str, int]:
                seen = []
                for _ in range(16):
                    begin, text = snapshot(revision)
                    revision = begin["revision"]
                    seen.append((revision, [line for line in text.splitlines() if line][-4:]))
                    if needle in text:
                        return begin, text, revision
                raise AssertionError((needle, seen))

            def key(kind: str, value: int, action: str = "press", **extra: object) -> None:
                request = {"request": "key", "key_kind": kind, "key_value": value, "action": action}
                request.update(extra)
                send(request)
                expect_result("input")

            welcome = read_record()
            require(welcome.get("record") == "welcome" and welcome.get("features") == 63, welcome)
            client_id = welcome["client_id"]
            begin, text = snapshot()
            revision = begin["revision"]
            require("NORMAL" in text, text)
            modes = interaction_state()
            require(modes["terminal_revision"] >= begin["terminal_revision"], modes)
            require(not modes["application_cursor_keys"] and not modes["application_keypad"], modes)
            require(not modes["bracketed_paste"] and not modes["focus_reporting"], modes)

            key("named", 5)
            begin, text, revision = observe_until("APP_CURSOR", revision)
            require("normal:1b5b41" in text, text)
            modes = interaction_state()
            require(modes["terminal_revision"] >= begin["terminal_revision"] and modes["application_cursor_keys"], modes)

            key("named", 5)
            begin, text, revision = observe_until("APP_KEYPAD", revision)
            require("app_cursor:1b4f41" in text, text)
            modes = interaction_state()
            require(modes["terminal_revision"] >= begin["terminal_revision"] and modes["application_keypad"], modes)

            key("named", 52)
            begin, text, revision = observe_until("FOCUS", revision)
            require("app_keypad:1b4f6b" in text, text)
            modes = interaction_state()
            require(modes["terminal_revision"] >= begin["terminal_revision"] and modes["focus_reporting"], modes)

            send({"request": "focus", "value": "in"})
            expect_result("input")
            begin, text, revision = observe_until("MOUSE", revision)
            require("focus:1b5b49" in text, text)
            modes = interaction_state()
            require(modes["terminal_revision"] >= begin["terminal_revision"], modes)
            require(modes["mouse_tracking"] == "any_event" and modes["mouse_protocol"] == "sgr_pixel", modes)

            send(
                {
                    "request": "mouse",
                    "kind": "press",
                    "button": "left",
                    "modifiers": 4,
                    "buttons_down": 1,
                    "row": 1,
                    "column": 2,
                    "pixel_x": 319,
                    "pixel_y": 239,
                }
            )
            expect_result("input")
            begin, text, revision = observe_until("PASTE", revision)
            require("mouse:1b5b3c31363b3332303b3234304d" in text, text)
            modes = interaction_state()
            require(modes["terminal_revision"] >= begin["terminal_revision"] and modes["bracketed_paste"], modes)

            send({"request": "paste", "bytes_hex": "780079"})
            expect_result("input")
            begin, text, revision = observe_until("KITTY_PRESS", revision)
            require("paste:1b5b3230307e7800791b5b3230317e" in text, text)
            modes = interaction_state()
            require(modes["terminal_revision"] >= begin["terminal_revision"] and modes["kitty_keyboard_flags"] == 31, modes)

            key("unicode", ord("a"))
            begin, text, revision = observe_until("KITTY_REPEAT", revision)
            require("kitty_press:1b5b393775" in text, text)

            key(
                "unicode",
                ord("a"),
                "repeat",
                modifiers=1,
                shifted=ord("A"),
                alternate=ord("q"),
                text="A",
            )
            begin, text, revision = observe_until("KITTY_RELEASE", revision)
            require("kitty_repeat:1b5b39373a36353a3131333b323a323b363575" in text, text)

            key("unicode", ord("a"), "release")
            begin, text, revision = observe_until("DONE", revision)
            require("kitty_release:1b5b39373b313a3375" in text, text)

            send({"request": "assign_leader", "client_id": client_id})
            expect_result("assign_leader")
            send({"request": "resize", "rows": 7, "columns": 20})
            expect_result("resize")
            begin, _ = snapshot()
            require(
                (begin["rows"], begin["columns"], begin["leader_present"], begin["you_are_leader"])
                == (7, 20, True, True),
                begin,
            )

            send({"request": "signal", "value": 15})
            expect_result("signal")
            for _ in range(30):
                begin, _ = snapshot()
                if begin["child_exited"]:
                    break
                time.sleep(0.02)
            require(begin["child_exited"] and begin["stream_closed"], begin)
            print("AX composition: PASS")
        finally:
            signal.alarm(0)
            if transport is not None:
                if transport.stdin:
                    transport.stdin.close()
                transport.terminate()
                try:
                    transport.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    transport.kill()
                    transport.wait()
            server.terminate()
            try:
                server.wait(timeout=1)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()


if __name__ == "__main__":
    main()
