#!/usr/bin/env python3
"""Run with a disposable parent directory: python3 test_install.py PATH."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

installer = Path(__file__).resolve().with_name("install.sh")
with tempfile.TemporaryDirectory(prefix="howl-install-", dir=sys.argv[1]) as directory:
    root = Path(directory)
    binary = root / "built"
    binary.write_text('#!/bin/sh\nprintf "%s" "$0" > "$HOWL_INSTALL_TEST_RECEIPT"\n')
    binary.chmod(0o755)
    home = root / 'home space $cash "quote" back\\slash'
    home.mkdir()
    data = root / "data space & amp"
    receipt = root / "launched"
    env = os.environ | {"HOME": str(home), "XDG_DATA_HOME": str(data),
                        "HOWL_INSTALL_TEST_RECEIPT": str(receipt)}

    def run(*args, success=True):
        result = subprocess.run(args, env=env, text=True, capture_output=True, timeout=10)
        assert (result.returncode == 0) == success, (args, result.stdout, result.stderr)

    run(str(installer), str(binary))
    desktop = data / "applications/io.github.laurenceguws.howl.desktop"
    run("desktop-file-validate", str(desktop))
    run("gio", "launch", str(desktop))
    for _ in range(40):
        if receipt.exists():
            break
        time.sleep(0.05)
    assert receipt.read_text() == str(home / ".local/bin/howl-app")
    run(str(installer), str(binary))
    before = desktop.read_bytes()
    run(str(installer), str(root / "missing"), success=False)
    assert desktop.read_bytes() == before
    target = home / ".local/bin/howl-app"
    target.unlink()
    target.symlink_to(binary)
    run(str(installer), str(binary), success=False)
    assert binary.exists()
    env["HOME"] = str(root / "percent%path")
    run(str(installer), str(binary), success=False)
    assert not Path(env["HOME"]).exists()
    env["HOME"] = "relative"
    run(str(installer), str(binary), success=False)
print("PASS: install, replace, GIO launch, special paths, missing binary, symlink and invalid-path rejection")
