#!/usr/bin/env python3
"""Run with a disposable parent directory: python3 test_install.py PATH."""
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import time

installer = Path(__file__).resolve().with_name("install.sh")
with tempfile.TemporaryDirectory(prefix="howl-install-", dir=sys.argv[1]) as directory:
    root = Path(directory)
    binary = root / "built"
    version = re.search(r'\.version = "([^"]+)"', installer.with_name("build.zig.zon").read_text())[1]
    binary.write_text(f'#!/bin/sh\nif [ "$1" = "--version" ]; then echo "Howl {version} (Zig SDL app)" >&2; exit 0; fi\nprintf "%s" "$0" > "$HOWL_INSTALL_TEST_RECEIPT"\n')
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
    installed = home / ".local/bin/howl-app"
    previous = installed.read_bytes()
    wrong = root / "wrong-version"
    wrong.write_text('#!/bin/sh\necho "Howl 0.0.0 (Zig SDL app)"\n')
    wrong.chmod(0o755)
    run(str(installer), str(wrong), success=False)
    assert installed.read_bytes() == previous
    assert desktop.read_bytes() == before
    assert not list(installed.parent.glob("howl-app.new.*"))
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
