#!/usr/bin/env python3
"""Black-box fail-closed and byte-bridge proof using Python stdlib only."""
from __future__ import annotations
import base64
import hashlib
import json
import os
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

GATEWAY = Path(sys.argv[1]).resolve()
ACCESS = 'test-access-assertion'
KEY = 'dGhlIHNhbXBsZSBub25jZQ=='
MAGIC = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'


def free_port() -> int:
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


class Echo:
    def __init__(self) -> None:
        self.port = free_port()
        self.accepted = 0
        self._stop = threading.Event()
        self._listener = socket.socket()
        self._listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._listener.bind(('127.0.0.1', self.port))
        self._listener.listen(4)
        self._listener.settimeout(.1)
        self._thread = threading.Thread(target=self._run, daemon=True)
    def start(self) -> None: self._thread.start()
    def close(self) -> None:
        self._stop.set(); self._listener.close(); self._thread.join(timeout=2)
    def _run(self) -> None:
        while not self._stop.is_set():
            try: conn, _ = self._listener.accept()
            except (socket.timeout, OSError): continue
            self.accepted += 1
            threading.Thread(target=self._echo, args=(conn,), daemon=True).start()
    @staticmethod
    def _echo(conn: socket.socket) -> None:
        with conn:
            conn.settimeout(2)
            try:
                while data := conn.recv(65536): conn.sendall(data)
            except OSError: pass


def read_head(sock: socket.socket) -> tuple[int, dict[str, str], bytes]:
    data = b''
    while b'\r\n\r\n' not in data:
        chunk = sock.recv(4096)
        if not chunk: raise AssertionError('HTTP EOF before headers')
        data += chunk
        if len(data) > 65536: raise AssertionError('HTTP headers unexpectedly large')
    head, rest = data.split(b'\r\n\r\n', 1)
    lines = head.decode('latin1').split('\r\n')
    status = int(lines[0].split()[1])
    headers: dict[str, str] = {}
    for line in lines[1:]:
        name, value = line.split(':', 1)
        headers[name.lower()] = value.strip()
    return status, headers, rest


def http_get(port: int, host: str, path: str, access: bool) -> tuple[int, dict[str, str], bytes]:
    with socket.create_connection(('127.0.0.1', port), timeout=2) as sock:
        extra = f'Cf-Access-Jwt-Assertion: {ACCESS}\r\n' if access else ''
        sock.sendall(f'GET {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n{extra}\r\n'.encode())
        status, headers, rest = read_head(sock)
        length = int(headers.get('content-length', '0'))
        body = bytearray(rest)
        while len(body) < length:
            data = sock.recv(length - len(body))
            if not data: break
            body += data
        return status, headers, bytes(body[:length])


def ws_open(port: int, host: str, origin: str | None, access: bool, key: str = KEY) -> tuple[socket.socket, int, dict[str, str]]:
    sock = socket.create_connection(('127.0.0.1', port), timeout=2)
    origin_header = f'Origin: {origin}\r\n' if origin is not None else ''
    access_header = f'Cf-Access-Jwt-Assertion: {ACCESS}\r\n' if access else ''
    request = (
        f'GET /socket HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\n'
        f'Connection: keep-alive, Upgrade\r\nSec-WebSocket-Version: 13\r\n'
        f'Sec-WebSocket-Key: {key}\r\n{origin_header}{access_header}\r\n'
    )
    sock.sendall(request.encode())
    status, headers, rest = read_head(sock)
    if status == 101: assert not rest
    return sock, status, headers


def send_masked(sock: socket.socket, opcode: int, payload: bytes) -> None:
    assert len(payload) < 126
    mask = b'\x11\x22\x33\x44'
    masked = bytes(value ^ mask[i % 4] for i, value in enumerate(payload))
    sock.sendall(bytes([0x80 | opcode, 0x80 | len(payload)]) + mask + masked)


def recv_frame(sock: socket.socket) -> tuple[int, bytes]:
    first = sock.recv(2)
    if len(first) != 2: raise AssertionError('short WebSocket header')
    opcode = first[0] & 0x0f
    assert first[0] & 0x80
    assert not first[1] & 0x80
    size = first[1] & 0x7f
    if size == 126: size = struct.unpack('!H', sock.recv(2))[0]
    elif size == 127: size = struct.unpack('!Q', sock.recv(8))[0]
    body = b''
    while len(body) < size:
        body += sock.recv(size - len(body))
    return opcode, body


def wait_ready(port: int) -> None:
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=.1): return
        except OSError: time.sleep(.02)
    raise AssertionError('gateway did not bind')


def main() -> None:
    echo = Echo(); echo.start()
    listen = free_port()
    host = f'howl.test:{listen}'
    origin = f'http://{host}'
    with tempfile.TemporaryDirectory(prefix='howl-gateway-test-') as raw:
        root = Path(raw)
        (root/'index.html').write_text('gateway-index\n')
        wire = root/'wire.wasm'; wire.write_bytes(b'wire')
        proc = subprocess.Popen([
            str(GATEWAY), str(listen), str(echo.port), host, origin,
            str(root), str(wire), '--require-access',
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            wait_ready(listen)
            assert http_get(listen, host, '/', False)[0] == 403
            status, headers, body = http_get(listen, host, '/', True)
            assert status == 200 and body == b'gateway-index\n'
            assert headers['content-security-policy'].startswith("default-src 'self'")
            assert http_get(listen, 'wrong.test', '/', True)[0] == 403
            assert echo.accepted == 0

            sock, status, _ = ws_open(listen, host, origin, False)
            sock.close(); assert status == 403 and echo.accepted == 0
            sock, status, _ = ws_open(listen, host, 'http://wrong.test', True)
            sock.close(); assert status == 403 and echo.accepted == 0
            sock, status, _ = ws_open(listen, host, origin, True, 'YQ==')
            sock.close(); assert status == 400 and echo.accepted == 0

            one, status, head = ws_open(listen, host, origin, True)
            assert status == 101
            expected = base64.b64encode(hashlib.sha1((KEY + MAGIC).encode()).digest()).decode()
            assert head['sec-websocket-accept'] == expected
            deadline = time.monotonic()+2
            while echo.accepted < 1 and time.monotonic() < deadline: time.sleep(.01)
            assert echo.accepted == 1
            send_masked(one, 2, b'opaque-howl-bytes')
            assert recv_frame(one) == (2, b'opaque-howl-bytes')

            two, status, _ = ws_open(listen, host, origin, True)
            assert status == 101
            deadline = time.monotonic()+2
            while echo.accepted < 2 and time.monotonic() < deadline: time.sleep(.01)
            assert echo.accepted == 2
            third, status, _ = ws_open(listen, host, origin, True)
            third.close(); assert status == 503 and echo.accepted == 2

            send_masked(one, 1, b'text-is-rejected')
            one.settimeout(2)
            assert one.recv(1) == b''
            one.close(); two.close()
            print(json.dumps({
                'status':'pass', 'access_before_upstream':True, 'host_origin_exact':True,
                'binary_bridge':True, 'text_rejected':True, 'websocket_capacity':2,
                'static_csp':True, 'upstream_accepts':echo.accepted,
            }))
        finally:
            proc.terminate()
            try: proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill(); proc.wait(timeout=2)
            stderr = proc.stderr.read() if proc.stderr else ''
            if proc.returncode not in (-15, 0):
                raise AssertionError(f'gateway exited {proc.returncode}: {stderr}')
            echo.close()

if __name__ == '__main__': main()
