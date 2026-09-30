#!/usr/bin/env python3
"""Compile and call generated Native bindings on the current host."""

import argparse
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def run(*args: str) -> str:
    result = subprocess.run(
        list(args), cwd=ROOT, text=True, encoding="utf-8", errors="replace",
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"{' '.join(args)} failed:\n{result.stdout}\n{result.stderr}")
    return result.stdout.strip()


def generate(header: str, out: str, config: str, clang: str) -> None:
    base = (
        "moon", "run", "-q", "cmd/main", "--", "generate", header,
        "--out", out, "--clang", clang, "--config", config,
    )
    print(run(*base))
    print(run(*base, "--check"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--clang", required=True)
    args = parser.parse_args()
    expected = json.loads((ROOT / "toolchain.json").read_text(encoding="utf-8"))
    version = run("moon", "version", "--all")
    assert expected["moon"] in version and expected["moonc"] in version
    core_manifest = (Path.home() / ".moon" / "lib" / "core" / "moon.mod").read_text(
        encoding="utf-8"
    )
    assert f'version = "{expected["core"]}"' in core_manifest
    assert f"clang version {expected['clang']}" in run(args.clang, "--version")
    print(run("moon", "check", "--target", "all", "--deny-warn", "--warn-list", "+73"))
    print(run("moon", "build", "--target", "all", "--deny-warn"))
    print(run("moon", "test", "--target", "all", "--deny-warn"))

    generate(
        "examples/native_fixture/fixture.h", "examples/native_fixture",
        "examples/native_fixture/config.json", args.clang,
    )
    assert run("moon", "run", "-q", "examples/native_fixture") == (
        "Native ABI fixture => 42, outputs and strings"
    )
    generate(
        "examples/buffer_fixture/fixture.h", "examples/buffer_fixture",
        "examples/buffer_fixture/config.json", args.clang,
    )
    assert run("moon", "run", "-q", "examples/buffer_fixture") == (
        "Buffer fixture => 42, zero, NULL, and invalid lengths"
    )
    generate(
        "examples/multi_fixture/fixture.h", "examples/multi_fixture",
        "examples/multi_fixture/config.json", args.clang,
    )
    assert run("moon", "run", "-q", "examples/multi_fixture") == (
        "Multi-output and resource fixture => named fields, close once, retain"
    )
    generate(
        "examples/value_fixture/fixture.h", "examples/value_fixture",
        "examples/value_fixture/config.json", args.clang,
    )
    assert run("moon", "run", "-q", "examples/value_fixture") == (
        "Value struct fixture => by-value arguments and return"
    )
    generate(
        "examples/callback_fixture/fixture.h", "examples/callback_fixture",
        "examples/callback_fixture/config.json", args.clang,
    )
    assert run("moon", "run", "-q", "examples/callback_fixture") == (
        "Callback fixture => call, unregister once, finalizer, closure release"
    )
    generate(
        "examples/sqlite/sqlite3.h", "examples/sqlite",
        "examples/sqlite/config.json", args.clang,
    )
    assert run("moon", "run", "-q", "examples/sqlite") == (
        "SELECT 42 => 42\nSQLite BLOB => 3 bytes, empty, NULL"
    )
    print("Portable Native verification passed.")


if __name__ == "__main__":
    main()
