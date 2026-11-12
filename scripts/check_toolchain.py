#!/usr/bin/env python3
"""Check the active MoonBit/Clang toolchain against toolchain.json.

`toolchain.json` records the toolchain the current release was verified on.
Its moonc and core versions are minimums: newer official toolchains are
accepted so CI keeps exercising the latest release and surfaces drift as
real check/build/test failures. Clang must match exactly when `--clang` is
given, because CI installs that pinned LLVM build.
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def triple(text: str, label: str) -> tuple[int, int, int]:
    match = re.search(r"(\d+)\.(\d+)\.(\d+)", text)
    if match is None:
        raise SystemExit(f"cannot parse {label} version from: {text!r}")
    return tuple(int(part) for part in match.groups())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--clang", help="Clang executable that must match toolchain.json")
    args = parser.parse_args()

    expected = json.loads((ROOT / "toolchain.json").read_text(encoding="utf-8"))
    version = subprocess.run(
        ["moon", "version", "--all"], text=True, encoding="utf-8", errors="replace",
        stdout=subprocess.PIPE, check=True,
    ).stdout
    print(version.strip())
    moonc_line = next((line for line in version.splitlines() if line.startswith("moonc")), "")
    core_manifest = (Path.home() / ".moon" / "lib" / "core" / "moon.mod").read_text(
        encoding="utf-8"
    )
    core_match = re.search(r'^version = "([^"]+)"', core_manifest, re.MULTILINE)
    if core_match is None:
        raise SystemExit("MoonBit core manifest has no version")
    print(f"core {core_match.group(1)}")

    failures = []
    if triple(moonc_line, "moonc") < triple(expected["moonc"], "expected moonc"):
        failures.append(f"moonc is older than the verified {expected['moonc']}")
    if triple(core_match.group(1), "core") < triple(expected["core"], "expected core"):
        failures.append(f"core is older than the verified {expected['core']}")
    if expected["moonc"] not in version:
        print(f"note: newer than the verified toolchain ({expected['moonc']})")

    if args.clang:
        clang = subprocess.run(
            [args.clang, "--version"], text=True, encoding="utf-8", errors="replace",
            stdout=subprocess.PIPE, check=True,
        ).stdout
        print(clang.splitlines()[0])
        if f"clang version {expected['clang']}" not in clang:
            failures.append(f"Clang must be {expected['clang']}")

    if failures:
        raise SystemExit("\n".join(failures))


if __name__ == "__main__":
    main()
    sys.exit(0)
