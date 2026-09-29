#!/usr/bin/env python3
"""Check handwritten MoonBit sources without reformatting generated bindings."""

import shutil
import subprocess
import tempfile
from pathlib import Path


root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="moonbindgen-fmt-") as temporary:
    project = Path(temporary)
    for path in root.rglob("*"):
        if any(part in {"_build", ".mooncakes", "submission", ".git"} for part in path.parts):
            continue
        if path.is_file() and (path.name in {"moon.mod", "moon.pkg"} or
                               path.suffix == ".mbt" and path.name != "bindings.mbt"):
            destination = project / path.relative_to(root)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)
    raise SystemExit(subprocess.run(["moon", "fmt", "--check"], cwd=project).returncode)
