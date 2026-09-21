#!/usr/bin/env python3

import json
import os
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time

MAGIC = b"HWLM"
VERSION = 1
HELLO = 1
WELCOME = 2
CREATE = 7
CLOSE = 8
SHUTDOWN = 11
RESULT = 12
OK = 1


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


def frame(kind, payload=b""):
    return struct.pack(">4sBB2xI", MAGIC, VERSION, kind, len(payload)) + payload


def recv_exact(sock, count):
    data = bytearray()
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise AssertionError("manager connection closed")
        data.extend(chunk)
    return bytes(data)


def recv_frame(sock):
    header = recv_exact(sock, 12)
    magic, version, kind, length = struct.unpack(">4sBB2xI", header)
    assert magic == MAGIC
    assert version == VERSION
    assert length <= 16 * 1024
    return kind, recv_exact(sock, length)


class Manager:
    def __init__(self, endpoint):
        assert endpoint.startswith("unix:")
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(5)
        self.sock.connect(endpoint[len("unix:"):])
        self.sock.sendall(frame(HELLO))
        kind, payload = recv_frame(self.sock)
        assert kind == WELCOME
        server_id, revision, pid, count, capacity, stopping = struct.unpack(
            ">QQIHHB7x", payload
        )
        assert server_id != 0
        assert revision == 1
        assert count == 0
        assert capacity == 16
        assert stopping == 0
        self.server_id = server_id
        self.pid = pid

    def close_socket(self):
        self.sock.close()

    def create(self, name):
        encoded = name.encode("ascii")
        assert 0 < len(encoded) <= 48
        payload = struct.pack(">HHBHHHB", 0, 0, len(encoded), 0, 0, 0, 0) + encoded
        self.sock.sendall(frame(CREATE, payload))
        kind, response = recv_frame(self.sock)
        assert kind == RESULT
        request_kind, code, session_id, revision = struct.unpack(">BB6xQQ", response)
        assert request_kind == CREATE
        assert code == OK
        assert session_id != 0
        return session_id, revision

    def close_session(self, session_id):
        self.sock.sendall(frame(CLOSE, struct.pack(">Q", session_id)))
        kind, response = recv_frame(self.sock)
        assert kind == RESULT
        request_kind, code, returned_id, revision = struct.unpack(">BB6xQQ", response)
        assert request_kind == CLOSE
        assert code == OK
        assert returned_id == session_id
        return revision

    def shutdown(self):
        self.sock.sendall(frame(SHUTDOWN))
        kind, response = recv_frame(self.sock)
        assert kind == RESULT
        request_kind, code, session_id, revision = struct.unpack(">BB6xQQ", response)
        assert request_kind == SHUTDOWN
        assert code == OK
        assert session_id == 0
        return revision


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
        manager = None
        try:
            line = proc.stdout.readline()
            if not line:
                stderr = proc.stderr.read()
                raise AssertionError(f"server exited before startup receipt: {stderr}")
            startup = json.loads(line)
            assert startup["schema"] == "howl.server/v2"
            assert startup["sessions"] == 0
            assert startup["capacity"] == 16
            manager = Manager(startup["manager"])
            assert manager.pid == proc.pid

            one_id, one_revision = manager.create("one")
            two_id, two_revision = manager.create("two")
            assert (one_id, two_id) == (1, 2)
            assert (one_revision, two_revision) == (2, 3)

            sessions = {
                "one": f"unix:{runtime}/one.sock",
                "two": f"unix:{runtime}/two.sock",
            }
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

            close_revision = manager.close_session(one_id)
            assert close_revision == 4
            assert not os.path.exists(f"{runtime}/one.sock")
            assert os.path.exists(f"{runtime}/two.sock")

            shutdown_revision = manager.shutdown()
            assert shutdown_revision == 5
            proc.wait(timeout=2)
            assert proc.returncode == 0

            print(json.dumps({
                "status": "pass",
                "schema": startup["schema"],
                "server_id": startup["server_id"],
                "session_ids": [one_id, two_id],
                "owner_pid": proc.pid,
                "children_before_close": children,
                "sessiond_children": 0,
                "independent_state": True,
                "dynamic_create_close": True,
                "managed_shutdown": True,
            }))
        finally:
            if manager is not None:
                manager.close_socket()
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
