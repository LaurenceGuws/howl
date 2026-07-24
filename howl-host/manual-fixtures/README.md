# Manual host receipts

These bounded scripts preserve distinct first-party host receipts that owner
tests cannot observe completely. They run as the existing host child command,
are not installed, and contain no product policy or reusable fixture framework.

- `basic-live.sh`: PTY bytes through VT, text preparation, GLES, and presentation.
- `geometry.sh`: DEC line geometry, baseline, decoration, color, and cursor drawing.
- `cursor-blink.sh`: compositor-visible cursor blink timing.
- `osc52.sh`: exact OSC 52 reply plus Wayland clipboard ownership.
- `window-control.sh`: exact ordered replies and one-way minimize request dispatch.
- `pointer-shape.sh`: cursor-shape set, stack, screen-bank, and reset presentation.
- `text-sizing.sh`: Kitty OSC 66 scale, fixed width, fractional alignment, decoration, and clipping.
- `drag-drop.py`: Kitty OSC 72 incoming copy-only `text/uri-list` bytes from one real Wayland drop.
- `kitty-graphics.py`: tracked Howl PNG sent as bounded raw RGBA, then cropped, scaled, offset, and layered placements.
- `kitty-animation.py`: bounded raw RGBA frames composed and advanced by monotonic host timing.
- `sixel.py`: bounded explicit-RGB Sixel decode through the common image plane.

From `howl-host`, run a receipt with:

```text
../.zig/zig build run -- window FONT ./manual-fixtures/RECEIPT.sh
```

Python receipts use the same command with their `.py` filename.

Each receipt exits on its own. Closing the window early remains valid.
