#!/usr/bin/env python3
"""End-to-end proof for the public Howl server-manager CLI."""

import json
import os
import signal
import subprocess
import sys
import tempfile
import time


def run(cli, *args, input_text=None, check=True):
    completed = subprocess.run(
        [cli, *args],
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    if check and completed.returncode != 0:
        raise AssertionError((args, completed.returncode, completed.stdout, completed.stderr))
    return completed


def run_json(cli, *args):
    completed = run(cli, *args)
    assert not completed.stderr, (args, completed.stderr)
    return json.loads(completed.stdout)


def child_comms(pid):
    path = f"/proc/{pid}/task/{pid}/children"
    try:
        text = open(path, encoding="ascii").read().strip()
    except FileNotFoundError:
        return []
    result = []
    for value in text.split():
        try:
            result.append(open(f"/proc/{value}/comm", encoding="ascii").read().strip())
        except FileNotFoundError:
            pass
    return result


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: server_multi.py HOWL")
    howl = os.path.abspath(sys.argv[1])

    with tempfile.TemporaryDirectory(prefix="howl-server-proof-") as runtime:
        proc = subprocess.Popen(
            [howl, "server", "run", runtime, "--shell", "/bin/sh"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        try:
            line = proc.stdout.readline()
            if not line:
                raise AssertionError(f"server exited before startup receipt: {proc.stderr.read()}")
            startup = json.loads(line)
            assert startup["schema"] == "howl.server/v2"
            assert startup["sessions"] == 0
            assert startup["capacity"] == 16
            manager = startup["manager"]

            status = run_json(howl, "server", "status", manager)
            assert status["schema"] == "howl.server.status/v1"
            assert status["server_id"] == startup["server_id"]
            assert status["pid"] == proc.pid
            assert status["sessions"] == 0
            assert status["capacity"] == 16
            assert status["stopping"] is False

            empty = run_json(howl, "session", "list", manager)
            assert empty["schema"] == "howl.server.sessions/v1"
            assert empty["sessions"] == []
            assert empty["roster_revision"] == "1"

            one = run_json(howl, "session", "create", manager, "one")
            two = run_json(howl, "session", "create", manager, "two")
            assert one["operation"] == "session.create" and one["session_id"] == "1"
            assert two["operation"] == "session.create" and two["session_id"] == "2"
            assert one["roster_revision"] == "2" and two["roster_revision"] == "3"

            duplicate = run(howl, "session", "create", manager, "one", check=False)
            assert duplicate.returncode != 0 and not duplicate.stdout
            duplicate_error = json.loads(duplicate.stderr)
            assert duplicate_error["schema"] == "howl.error/v1"
            assert duplicate_error["operation"] == "session.create"
            assert duplicate_error["code"] == "name_exists"
            assert "stack trace" not in duplicate.stderr and "error return context" not in duplicate.stderr

            listed = run_json(howl, "session", "list", manager)
            assert [row["name"] for row in listed["sessions"]] == ["one", "two"]
            assert [row["session_id"] for row in listed["sessions"]] == ["1", "2"]
            shown = run_json(howl, "session", "show", manager, "two")
            assert shown["session"]["session_id"] == "2"
            assert shown["session"]["state"] == "running"

            stale = run(
                howl,
                "session",
                "close",
                manager,
                "one",
                "--expect-id",
                "99",
                check=False,
            )
            assert stale.returncode != 0 and not stale.stdout
            stale_error = json.loads(stale.stderr)
            assert stale_error["code"] == "stale_identity"

            sessions = {
                "one": f"unix:{runtime}/one.sock",
                "two": f"unix:{runtime}/two.sock",
            }
            run(howl, "type", sessions["one"], "--stdin", input_text="echo ONE_CANARY\n")
            run(howl, "type", sessions["two"], "--stdin", input_text="echo TWO_CANARY\n")
            time.sleep(0.15)
            one_text = run(howl, "snapshot", sessions["one"], "--text").stdout
            two_text = run(howl, "snapshot", sessions["two"], "--text").stdout
            assert "ONE_CANARY" in one_text and "TWO_CANARY" not in one_text
            assert "TWO_CANARY" in two_text and "ONE_CANARY" not in two_text

            children = child_comms(proc.pid)
            assert children.count("sh") >= 2, children
            assert "howl-sessiond" not in children, children

            closed = run_json(howl, "session", "close", manager, "one", "--expect-id", "1")
            assert closed["operation"] == "session.close" and closed["session_id"] == "1"
            assert not os.path.exists(f"{runtime}/one.sock")
            assert os.path.exists(f"{runtime}/two.sock")
            remaining = run_json(howl, "session", "list", manager)
            assert [row["name"] for row in remaining["sessions"]] == ["two"]

            shutdown = run_json(howl, "server", "shutdown", manager)
            assert shutdown["operation"] == "server.shutdown"
            proc.wait(timeout=2)
            assert proc.returncode == 0

            print(json.dumps({
                "status": "pass",
                "schema": startup["schema"],
                "server_id": startup["server_id"],
                "session_ids": [1, 2],
                "owner_pid": proc.pid,
                "children_before_close": children,
                "sessiond_children": 0,
                "cli_manager_surface": True,
                "structured_errors": True,
                "aba_guard": True,
                "dynamic_create_close": True,
                "managed_shutdown": True,
            }))
        finally:
            if proc.poll() is None:
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait(timeout=2)


if __name__ == "__main__":
    main()
