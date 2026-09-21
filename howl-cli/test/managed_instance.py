#!/usr/bin/env python3
"""Public CLI proof for Instance interaction routed through one Howl Server."""

import json
import subprocess
import sys
import time


def invoke(cli, *args, timeout=5, check=True):
    result = subprocess.run(
        [cli, *args],
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    if check and result.returncode != 0:
        raise AssertionError((args, result.returncode, result.stdout, result.stderr))
    return result


def json_out(result):
    assert not result.stderr, result.stderr
    return json.loads(result.stdout)


def main():
    cli = sys.argv[1]
    server = subprocess.Popen(
        [cli, "server", "run", "tcp:0"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    endpoint = None
    session_id = None
    instance_id = None
    try:
        receipt_line = server.stdout.readline()
        assert receipt_line, server.stderr.read()
        receipt = json.loads(receipt_line)
        assert receipt["schema"] == "howl.server.run/v1", receipt
        endpoint = receipt["endpoint"]
        assert endpoint.startswith("tcp://127.0.0.1:"), endpoint

        session = json_out(
            invoke(cli, "server", "session", "create", endpoint, "managed-cli")
        )
        session_id = session["session_id"]
        instance = json_out(
            invoke(
                cli,
                "server",
                "instance",
                "create",
                endpoint,
                session_id,
                "--shell",
                "/bin/sh",
                "--command",
                "printf 'MANAGED_CLI_READY\\n'; exec cat",
                "--rows",
                "8",
                "--columns",
                "40",
                "--history-rows",
                "32",
            )
        )
        instance_id = instance["instance_id"]
        target = ("--server", endpoint, session_id, instance_id)

        snapshot = invoke(cli, "instance", "snapshot", *target, "--text")
        assert "MANAGED_CLI_READY" in snapshot.stdout, snapshot.stdout

        typed = json_out(
            invoke(cli, "instance", "type", *target, "MANAGED_CLI_INPUT\n")
        )
        assert typed == {
            "schema": "howl.action/v1",
            "operation": "type",
            "result": "ok",
        }, typed

        deadline = time.monotonic() + 2
        while True:
            snapshot = invoke(cli, "instance", "snapshot", *target, "--text")
            if "MANAGED_CLI_INPUT" in snapshot.stdout:
                break
            if time.monotonic() >= deadline:
                raise AssertionError(snapshot.stdout)
            time.sleep(0.01)

        resize = json_out(invoke(cli, "instance", "resize", *target, "9", "33"))
        assert resize["operation"] == "resize", resize
        compact = json_out(invoke(cli, "instance", "snapshot", *target))
        assert compact["geometry"] == {"rows": 9, "columns": 33}, compact["geometry"]

        state = json_out(invoke(cli, "instance", "state", *target))
        assert state["schema"] == "howl.state/v1", state

        # Exact routing failures remain typed Instance-client failures, not Server CRUD.
        missing = invoke(
            cli,
            "instance",
            "state",
            "--server",
            endpoint,
            session_id,
            "999999",
            check=False,
        )
        assert missing.returncode == 1, missing
        error = json.loads(missing.stderr)
        assert error["operation"] == "instance.state", error
        assert error["code"] == "InstanceNotFound", error

        json_out(
            invoke(
                cli,
                "server",
                "instance",
                "close",
                endpoint,
                session_id,
                instance_id,
            )
        )
        instance_id = None
        json_out(invoke(cli, "server", "session", "close", endpoint, session_id))
        session_id = None
        print("Howl managed CLI interaction: PASS")
    finally:
        if endpoint and session_id and instance_id:
            invoke(
                cli,
                "server",
                "instance",
                "close",
                endpoint,
                session_id,
                instance_id,
                check=False,
            )
        if endpoint and session_id:
            invoke(cli, "server", "session", "close", endpoint, session_id, check=False)
        server.terminate()
        try:
            server.wait(timeout=3)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait(timeout=3)
        stderr = server.stderr.read()
        assert not stderr, stderr


if __name__ == "__main__":
    main()
