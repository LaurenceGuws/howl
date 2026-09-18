#!/usr/bin/env python3

import json
import os
import signal
import subprocess
import sys
import tempfile
import time


def run(*argv, input_text=None):
    return subprocess.run(
        argv,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        timeout=10,
    )


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
            [howl, "server", runtime, "one", "two", "--shell", "/bin/sh"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        try:
            line = proc.stdout.readline()
            if not line:
                stderr = proc.stderr.read()
                raise AssertionError(f"server exited before manifest: {stderr}")
            manifest = json.loads(line)
            assert manifest["schema"] == "howl.server/v1"
            sessions = {value["name"]: value["endpoint"] for value in manifest["sessions"]}
            assert set(sessions) == {"one", "two"}

            run(howl, "type", sessions["one"], "--stdin", input_text="echo ONE_CANARY\n")
            run(howl, "type", sessions["two"], "--stdin", input_text="echo TWO_CANARY\n")
            time.sleep(0.15)

            one = run(howl, "snapshot", sessions["one"], "--text").stdout
            two = run(howl, "snapshot", sessions["two"], "--text").stdout
            assert "ONE_CANARY" in one
            assert "TWO_CANARY" not in one
            assert "TWO_CANARY" in two
            assert "ONE_CANARY" not in two

            children = child_comms(proc.pid)
            assert children.count("sh") >= 2, children
            assert "howl-sessiond" not in children, children

            print(json.dumps({
                "status": "pass",
                "schema": manifest["schema"],
                "sessions": sorted(sessions),
                "owner_pid": proc.pid,
                "children": children,
                "sessiond_children": 0,
                "independent_state": True,
            }))
        finally:
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
