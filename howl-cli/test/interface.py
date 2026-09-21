#!/usr/bin/env python3
"""CLI help/usage/error presentation must never expose Zig return traces."""

import json
import subprocess
import sys


def invoke(cli, *args):
    return subprocess.run([cli, *args], text=True, capture_output=True, timeout=5)


def main():
    cli = sys.argv[1]
    for args in [
        ("--help",),
        ("help",),
        ("server", "--help"),
        ("server", "run", "--help"),
        ("session", "--help"),
        ("session", "create", "--help"),
        ("snapshot", "--help"),
        ("key", "--help"),
    ]:
        result = invoke(cli, *args)
        assert result.returncode == 0, (args, result)
        assert result.stdout and "usage:" in result.stdout, (args, result.stdout)
        assert not result.stderr, (args, result.stderr)

    for args, operation in [
        (("nonsense",), "nonsense"),
        (("session", "create"), "session.create"),
        (("server", "status"), "server.status"),
    ]:
        result = invoke(cli, *args)
        assert result.returncode == 64, (args, result)
        assert not result.stdout
        error = json.loads(result.stderr)
        assert error["schema"] == "howl.error/v1"
        assert error["operation"] == operation, (args, error)
        assert error["code"] == "InvalidArguments"
        assert "stack trace" not in result.stderr
        assert "error return context" not in result.stderr

    print("Howl CLI interface: PASS (clean help and structured usage failures)")


if __name__ == "__main__":
    main()
