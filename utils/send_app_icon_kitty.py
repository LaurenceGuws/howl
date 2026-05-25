#!/usr/bin/env python3

import argparse
import base64
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ICON = ROOT / "howl-linux-host" / "assets" / "icon" / "howl_window_icon.png"
ESC = "\x1b"
ST = f"{ESC}\\"
CHUNK_SIZE = 4096


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send the Howl host app icon over the Kitty graphics protocol.",
    )
    parser.add_argument(
        "--image",
        type=Path,
        default=DEFAULT_ICON,
        help=f"PNG to send (default: {DEFAULT_ICON})",
    )
    parser.add_argument("--id", type=int, default=4242, help="Kitty image id")
    parser.add_argument("--cols", type=int, default=8, help="Display width in terminal cells")
    parser.add_argument("--rows", type=int, default=4, help="Display height in terminal cells")
    parser.add_argument(
        "--no-move-cursor",
        action="store_true",
        help="Do not request Kitty to move the cursor after placement",
    )
    return parser.parse_args()


def write_escape(data: bytes) -> None:
    with open("/dev/tty", "wb", buffering=0) as tty:
        tty.write(data)


def main() -> int:
    args = parse_args()
    image_path = args.image.resolve()
    payload = image_path.read_bytes()
    encoded = base64.b64encode(payload).decode("ascii")

    move = "q=2" if args.no_move_cursor else f"a=T,c={args.cols},r={args.rows}"

    for offset in range(0, len(encoded), CHUNK_SIZE):
        chunk = encoded[offset : offset + CHUNK_SIZE]
        more = 1 if offset + CHUNK_SIZE < len(encoded) else 0
        if offset == 0:
            control = f"i={args.id},f=100,t=d,{move},m={more}"
        else:
            control = f"m={more}"
        write_escape(f"{ESC}_G{control};{chunk}{ST}".encode("ascii"))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
