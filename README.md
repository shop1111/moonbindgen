# MoonBindgen

MoonBindgen is a pure MoonBit Native command-line generator for conservative C FFI declarations. It delegates C parsing to Clang 23, converts the JSON AST into a typed declaration model, lowers only verified direct-ABI types, and writes deterministic MoonBit declarations together with an auditable report.

The project deliberately does not pretend that syntax implies ownership. It rejects callbacks, by-value structs, output pointers, returned strings, variadic functions, and pointers whose lifetime is unclear. A configured call-scoped `const char *` input is the only string shortcut: it becomes `Bytes` with `#borrow`.

## Why this project

C interoperability is an ecosystem multiplier: one trustworthy generator can reduce the repetitive and error-prone first step of binding databases, compression libraries, parsers, and operating-system APIs. The hard part is not printing `extern "C"`; it is preserving declaration provenance, resolving typedefs without importing unrelated functions, making unsafe gaps visible, and producing output that reviewers can reproduce.

[klaseca/moonbit-bindgen](https://github.com/klaseca/moonbit-bindgen) is an important existing reference. It is a TypeScript framework with configurable source processing and stub generation. MoonBindgen takes a different technical route: the generator itself is MoonBit, Clang's AST is the source of declaration facts, unsupported ABI cases are rejected conservatively, every decision appears in a versioned report, and Native compile/link/call fixtures plus SQLite exercise the result. The rationale is therefore auditability and implementation diversity, not merely whether another project has been published to Mooncakes.

## Architecture

```text
C header + config-v1
        │
        ▼
Clang 23 JSON AST ──► provenance-aware declaration model
                            │
             typedef/enum/opaque-type environment
                            │
                            ▼
                  conservative ABI lowering
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
        bindings.mbt          moonbindgen-report-v2
```

The main header controls which declarations are emitted. Included headers may supply typedef and enum facts, but their functions are not emitted. Clang nodes that omit a repeated filename inherit the most recent explicit provenance; malformed or contradictory declaration structures stop generation instead of being guessed.

## Requirements and quick start

- MoonBit `0.1.20260819` with the Native target
- Clang `23.x`; CI and local evidence use LLVM `23.1.1`
- Windows x64 is the currently verified environment, not a cross-platform promise

```powershell
moon run -q cmd/main -- generate fixtures/basic.h --out _build/basic --clang 'C:\Program Files\LLVM\bin\clang.exe'
moon run -q cmd/main -- generate fixtures/basic.h --out _build/basic --clang 'C:\Program Files\LLVM\bin\clang.exe' --check
```

Arguments after `--` go directly to Clang, for example `-- -Ivendor/include -DFEATURE=1`. `--check` compares both generated files and writes nothing; drift exits with code 6. Run `--help` for the complete interface. Exit codes distinguish usage/configuration (2), Clang (3), generation policy (4), output I/O (5), and drift (6).

## Configuration v1

`--config <json>` accepts only the versioned schema below. Function filters are exact names. Renames are normalized as MoonBit identifiers and collision-checked. Type overrides are restricted to `Bool`, `Byte`, `Int`, `UInt`, `Int64`, `UInt64`, `Float`, and `Double`; they cannot inject source text.

```json
{
  "schema": "moonbindgen-config-v1",
  "include_functions": ["library_open"],
  "exclude_functions": [],
  "renames": { "library_open": "open_library" },
  "type_overrides": { "library_size_t": "UInt64" },
  "utf8_inputs": ["library_open.path"],
  "unsupported_policy": "error"
}
```

`unsupported_policy` is `report` by default. With `error`, any unsupported declaration rejects the whole generation before official output files are replaced.

## Supported ABI surface

| C declaration | MoonBit output | Policy |
| --- | --- | --- |
| `char`, signed/unsigned fixed mappings | `Byte`, `Int`, `UInt`, `Int64`, `UInt64` | Direct value ABI |
| `float`, `double` | `Float`, `Double` | Direct value ABI |
| typedef chains and 32-bit enums | Canonical scalar / `Int` | Resolved from Clang facts |
| pointer to an opaque struct typedef | `#external` type | Raw pointer; caller owns lifetime rules |
| configured input `const char *` | `Bytes` plus `#borrow` | Valid only for the duration of the call |
| returned strings, output pointers, callbacks, variadics, by-value structs | none | Reported and skipped, or rejected in strict mode |

MoonBindgen emits a raw FFI layer. It does not generate a general C shim, callback trampolines, resource-safe wrappers, C++, or broad platform guarantees in version 0.1.x.

## Auditable report v2

`report.json` uses `moonbindgen-report-v2`. It records the Clang version and target, referenced include files, declaration kind and source line, original C signature, emitted MoonBit declaration, status, stable reason code, and summary counts. Existing v2 fields and reason codes will not be repurposed within 0.1.x; compatible fields may be added.

```json
{
  "schema": "moonbindgen-report-v2",
  "clang": { "version": "clang version 23.1.1 ...", "target": "x86_64-pc-windows-msvc" },
  "summary": { "functions_generated": 4, "functions_skipped": 0, "unsupported": 0 },
  "declarations": [{ "c_name": "abi_add", "status": "generated", "reason_code": "generated" }]
}
```

## Verification evidence

```powershell
./scripts/verify.ps1
```

The gate runs strict Native check/build/test, coverage analysis, two-run byte determinism, report schema assertions, include provenance, invalid-header rejection, artifact drift checks, a generated C fixture that compiles/links/calls scalars and a borrowed UTF-8 input, and the SQLite query below.

`examples/sqlite` vendors the official SQLite 3.53.4 amalgamation. On Clang 23.1.1, MoonBindgen generates 128 functions and reports 170 unsupported functions. A small handwritten shim demonstrates the explicitly out-of-scope output-pointer boundary for open/prepare; generated declarations then execute `SELECT 42` through `sqlite3_step`, `sqlite3_column_int`, `sqlite3_finalize`, and `sqlite3_close`.

```powershell
moon run -q examples/sqlite
# SELECT 42 => 42
```

Exact upstream provenance, checksums, licensing, and the one comment-only local edit are recorded in [THIRD_PARTY.md](THIRD_PARTY.md).

## Release hygiene

`.moonignore` keeps fixtures, examples, scripts, CI configuration, tests, the local competition charter, and `submission/` out of the Mooncakes package. The SQLite amalgamation is marked vendored for GitHub language statistics. Before a future release, run the full verification gate, `moon info`, format-check the handwritten MoonBit packages, run `moon doc`, and inspect `moon package --list`; publishing, tags, releases, and Gitlink import are intentionally outside this milestone.
