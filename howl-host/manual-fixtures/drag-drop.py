#!/usr/bin/env python3
"""Manual Kitty OSC 72 incoming copy-only Wayland drop receipt."""

import base64
import os
import select
import signal
import sys
import termios
import time
import tty

OSC = b"\x1b]72;"
ST = b"\x1b\\"
TIMEOUT = 60.0


def send(metadata: bytes, payload: bytes = b"") -> None:
    os.write(sys.stdout.fileno(), OSC + metadata + b";" + payload + ST)


class Receiver:
    def __init__(self) -> None:
        self.data = bytearray()

    def receive(self, deadline: float) -> tuple[dict[bytes, bytes], bytes]:
        while time.monotonic() < deadline:
            start = self.data.find(OSC)
            end = self.data.find(ST, start + len(OSC)) if start >= 0 else -1
            if start >= 0 and end >= 0:
                body = bytes(self.data[start + len(OSC) : end])
                del self.data[: end + len(ST)]
                return decode(body)
            ready, _, _ = select.select([sys.stdin.fileno()], [], [], 0.2)
            if not ready:
                continue
            chunk = os.read(sys.stdin.fileno(), 4096)
            if not chunk:
                raise RuntimeError("terminal closed before OSC 72 reply")
            self.data.extend(chunk)
        raise TimeoutError("timed out waiting for OSC 72")


def decode(body: bytes) -> tuple[dict[bytes, bytes], bytes]:
    metadata, separator, payload = body.partition(b";")
    if not separator:
        payload = b""
    fields = {}
    for field in metadata.split(b":"):
        key, equals, value = field.partition(b"=")
        if not equals:
            raise RuntimeError("malformed OSC 72 metadata")
        fields[key] = value
    return fields, payload


def main() -> int:
    def interrupted(_signal: int, _frame: object) -> None:
        raise KeyboardInterrupt

    signal.signal(signal.SIGHUP, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    old = termios.tcgetattr(sys.stdin.fileno())
    tty.setraw(sys.stdin.fileno())
    receiver = Receiver()
    try:
        send(b"t=q:i=72")
        fields, payload = receiver.receive(time.monotonic() + 5)
        if fields != {b"t": b"q", b"i": b"72"} or payload:
            raise RuntimeError("unexpected OSC 72 capability reply")
        send(b"t=a:i=72", b"text/uri-list")
        os.write(sys.stderr.fileno(), b"Drag one harmless Dolphin file into this window.\n")

        offered: list[bytes] = []
        while True:
            fields, payload = receiver.receive(time.monotonic() + TIMEOUT)
            if fields.get(b"t") not in (b"m", b"M"):
                continue
            if payload:
                offered = payload.split(b" ")
            if fields[b"t"] == b"m":
                if b"text/uri-list" in offered and fields.get(b"o") in (b"1", b"3"):
                    send(b"t=m:i=72:o=1", b"text/uri-list")
                else:
                    send(b"t=m:i=72:o=0")
                continue
            if b"text/uri-list" not in offered:
                raise RuntimeError("drop omitted text/uri-list")
            index = offered.index(b"text/uri-list") + 1
            send(f"t=r:i=72:x={index}".encode())
            break

        result = bytearray()
        while True:
            fields, payload = receiver.receive(time.monotonic() + TIMEOUT)
            if fields.get(b"t") == b"R":
                raise RuntimeError(f"terminal rejected data request: {payload!r}")
            if fields.get(b"t") != b"r" or int(fields.get(b"x", b"0")) != index:
                continue
            if payload:
                result.extend(base64.b64decode(payload, validate=True))
            if fields.get(b"m") == b"0":
                break
        send(b"t=r:i=72:o=1")
        send(b"t=A:i=72")
    finally:
        termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, old)

    sys.stdout.buffer.write(b"PASS: exact opaque text/uri-list payload follows\n")
    sys.stdout.buffer.write(result)
    if not result.endswith(b"\n"):
        sys.stdout.buffer.write(b"\n")
    sys.stdout.flush()
    time.sleep(5)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as failure:
        print(f"FAIL: {failure}", file=sys.stderr)
        raise SystemExit(1)
