# MoonBindgen

MoonBindgen is a pure MoonBit Native command-line generator for conservative C FFI declarations. It delegates C parsing to Clang 23, converts the JSON AST into a typed declaration model, lowers only verified direct-ABI types, and writes deterministic MoonBit declarations together with an auditable report.

The project deliberately does not pretend that syntax implies ownership. It rejects callbacks, by-value structs, variadic functions, and pointers whose lifetime is unclear. Explicit configuration enables named outputs, managed opaque resources, borrowed/owned UTF-8 returns, and byte buffers with stated length and lifetime policies; these functions receive generated C bridges. A configured call-scoped `const char *` input becomes `Bytes` with `#borrow`.

## Why this project

C interoperability is an ecosystem multiplier: one trustworthy generator can reduce the repetitive and error-prone first step of binding databases, compression libraries, parsers, and operating-system APIs. The hard part is not printing `extern "C"`; it is preserving declaration provenance, resolving typedefs without importing unrelated functions, making unsafe gaps visible, and producing output that reviewers can reproduce.

[klaseca/moonbit-bindgen](https://github.com/klaseca/moonbit-bindgen) is an important existing reference. It is a TypeScript framework with configurable source processing and stub generation. MoonBindgen takes a different technical route: the generator itself is MoonBit, Clang's AST is the source of declaration facts, unsupported ABI cases are rejected conservatively, every decision appears in a versioned report, and Native compile/link/call fixtures plus SQLite exercise the result. The rationale is therefore auditability and implementation diversity, not merely whether another project has been published to Mooncakes.

## Architecture

```text
C header + config-v1/v2
        │
        ▼
Clang 23 JSON AST ──► provenance-aware declaration model
                            │
             typedef/enum/opaque-type environment
                            │
                            ▼
             ABI and policy-checked lowering
                            │
         ┌──────────────┼────────────────┐
         ▼              ▼                ▼
   bindings.mbt   optional C shim   report.json (v2)
```

The main header controls which declarations are emitted. Included headers may supply typedef and enum facts, but their functions are not emitted. Clang nodes that omit a repeated filename inherit the most recent explicit provenance; malformed or contradictory declaration structures stop generation instead of being guessed.

## Requirements and installation

- MoonBit `0.1.20260920 (914d7da)` with Moonc/Core `0.10.14+7d59c7ec9`
- Clang `23.x`; CI and local evidence use LLVM `23.1.1`
- Windows x64 and Ubuntu 24.04 are verified with MoonBit/Core and Clang 23.1.1. The Linux CI runner regenerates, compiles, and calls the Native fixtures and SQLite example, then reruns them with AddressSanitizer instrumentation.

The checked release toolchain is recorded in [`toolchain.json`](toolchain.json). CI rejects a different compiler or core version instead of silently accepting formatter or diagnostic drift.

To consume the generator as a library:

```powershell
moon add shop1111/moonbindgen@0.4.0
```

Add the root package to `moon.pkg`:

```text
import {
  "shop1111/moonbindgen" @bindgen,
}
```

The public entry points are `generate`, `generate_with_config`, `generate_with_metadata`, and `parse_config`. They accept Clang AST JSON; invoking Clang remains the responsibility of the CLI or the embedding application.

```moonbit
let config_text =
  #|{"schema":"moonbindgen-config-v1","unsupported_policy":"report"}
let config = @bindgen.parse_config(config_text)
let result = @bindgen.generate_with_config(clang_ast_json, "library.h", config)
println(result.bindings)
```

Windows users can also download `moonbindgen-v0.4.0-windows-x86_64.zip` from the GitHub Release after the v0.4.0 gates pass, extract `moonbindgen.exe`, and keep Clang 23 available separately. The executable is not a general C/C++ compiler bundle.

## CLI quick start

```powershell
moon run -q cmd/main -- generate fixtures/basic.h --out _build/basic --clang 'C:\Program Files\LLVM\bin\clang.exe'
moon run -q cmd/main -- generate fixtures/basic.h --out _build/basic --clang 'C:\Program Files\LLVM\bin\clang.exe' --check
```

Arguments after `--` go directly to Clang, for example `-- -Ivendor/include -DFEATURE=1`. `--check` compares all generated artifacts and writes nothing; drift exits with code 6. Run `--help` for the complete interface. Exit codes distinguish usage/configuration (2), Clang (3), generation policy (4), output I/O (5), and drift (6).

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

### Explicit C bridges

The SQLite example uses the additional config-v1 fields below:

```json
{
  "schema": "moonbindgen-config-v1",
  "utf8_inputs": ["sqlite3_open.filename", "sqlite3_prepare_v2.zSql"],
  "output_params": ["sqlite3_open.ppDb", "sqlite3_prepare_v2.ppStmt"],
  "null_inputs": ["sqlite3_prepare_v2.pzTail"],
  "utf8_borrowed_returns": ["sqlite3_libversion"]
}
```

`output_params` selects exactly one scalar `T*` or opaque-handle `T**` output for a function returning an `int` status; its MoonBit wrapper returns `(Int, T)`. The status and output value are both preserved on failure, so callers must follow the C library's cleanup contract. `null_inputs` omits an explicitly nullable pointer argument. Other output pointers remain unsupported.

`utf8_borrowed_returns` copies a borrowed `char*` / `const char*` before its owner can change. `utf8_owned_returns` maps an owned `char*` function to a declared `void free_name(char*)` or `void free_name(void*)` function; the bridge copies first and calls that function once. Both yield `String?`: C `NULL` becomes `None`, and malformed UTF-8 raises a decoding error. An owned return without a declared compatible release function is rejected; the caller must confirm the library's ownership contract.

When a bridge is needed, generation also writes `bindings_shim.c`. Place it alongside the C header, or provide the header's directory to the C compiler; include the generated file in the consumer package's `native-stub` list and import `moonbitlang/core/encoding/utf8` in `moon.pkg` for string wrappers. For example, `examples/sqlite/moon.pkg` uses `"native-stub": [ "sqlite3.c", "bindings_shim.c" ]`. `--check` compares all generated artifacts, including the presence or absence of this C file.

## Configuration v2: byte buffers

`moonbindgen-config-v2` keeps the v1 filters and string policies. New buffer policies use zero-based C parameter positions, so they also work when a header omits parameter names. A policy must identify the pointer and length; MoonBindgen checks their Clang types and emits a C bridge with a range check. `type_overrides` are rejected in v2 because an arbitrary scalar remapping cannot establish ABI compatibility.

```json
{
  "schema": "moonbindgen-config-v2",
  "buffers": [{
    "function": "sqlite3_bind_blob",
    "pointer": 2,
    "length": 3,
    "direction": "in",
    "retention": "copy",
    "copy_parameter": 4,
    "copy_symbol": "SQLITE_TRANSIENT"
  }],
  "return_buffers": [{
    "function": "sqlite3_column_blob",
    "length_function": "sqlite3_column_bytes",
    "length_args": [0, 1],
    "null_function": "sqlite3_column_type",
    "null_symbol": "SQLITE_NULL"
  }]
}
```

An `in` buffer accepts MoonBit `Bytes`; its length is taken from the value and checked before C is called. Use `retention: "call"` only if C does not retain the pointer. For a C API that copies during the call, use `retention: "copy"` and, when required, a declared destructor/copy token parameter such as SQLite's `SQLITE_TRANSIENT`. The token fields accept C identifiers only, and the generated C must compile against the supplied header. An `out` buffer takes an `Int` capacity, rejects negative values, and returns `Bytes` or `(Int, Bytes)` when C returns an integer status. Callers must interpret status before reading output.

`return_buffers` copies a borrowed `const` byte pointer using a companion length function before another C call can invalidate it. It returns `Bytes?`: `None` denotes the configured null discriminator; an empty non-null value is `Some(Bytes::make(0, b'\x00'))`. Without a discriminator, a zero-length NULL is treated as empty. A negative length, a length above `INT32_MAX`, or a NULL pointer with positive length raises an error. Companion functions must have declared signatures matching the selected argument positions. Current v2 supports one buffer policy per function, byte pointers with integer lengths, and functions returning `int` or `void`; unsupported combinations remain in the report.

For `short`, `unsigned short`, `long`, `unsigned long`, `size_t`, `ptrdiff_t`, and `_Bool`, v2 emits C bridges with target-aware range checks instead of assuming a MoonBit scalar has the same C ABI. The generated C is compiled by the consumer's target C compiler. The original v1 schema and its outputs remain available.

## Configuration v2: named outputs and resources

`multi_outputs` names two or more scalar or opaque-handle outputs by zero-based C argument position. The generated function returns a public struct with those fields and a `status` field when C returns `int`. Values are initialized before C is called, so a failure status cannot expose uninitialized memory; callers still have to follow the library's error contract before using them. Target-dependent scalar fields are read through C accessors, and the raw C result object is released after the public value has been assembled.

```json
{
  "schema": "moonbindgen-config-v2",
  "multi_outputs": [{
    "function": "make_pair",
    "outputs": [
      { "index": 1, "name": "left" },
      { "index": 2, "name": "right" },
      { "index": 3, "name": "handle" }
    ]
  }],
  "resources": [{
    "name": "token",
    "create": "token_new",
    "release": "token_free",
    "retain": "token_retain",
    "views": ["token_borrow"]
  }]
}
```

A resource policy requires a create function returning an opaque pointer and an exact-handle `void` release function. The generated managed type owns a shared state: `close()` releases at most once and reports whether it released the handle; the C finalizer releases an unclosed handle when the last MoonBit reference is dropped. An optional `void` retain function enables a second managed owner through `retain()`. A listed same-handle view function returns a view that holds its owner, preventing finalization while the view lives. Use `view.with_raw(fn(raw) { ... })` to keep that owner alive throughout a C call. Its `unsafe_raw()` method only checks that the owner is open when it returns; the caller must keep the view alive for the entire use of the raw pointer. The `*_raw` declarations remain available for APIs whose lifetime rules need manual handling. These wrappers do not claim cross-thread synchronization.

If a configured release function returns a status instead of `void`, MoonBindgen emits the raw create declaration and marks it `manual_resource_management` in the report. A generated close/finalizer cannot safely hide a failing release operation. Current resource views take and return the same opaque handle; views of other pointer types remain unsupported.

## Supported ABI surface

| C declaration | MoonBit output | Policy |
| --- | --- | --- |
| `char`, signed/unsigned fixed mappings | `Byte`, `Int`, `UInt`, `Int64`, `UInt64` | Direct value ABI |
| `float`, `double` | `Float`, `Double` | Direct value ABI |
| typedef chains and 32-bit enums | Canonical scalar / `Int` | Resolved from Clang facts |
| pointer to an opaque struct typedef | `#external` type | Raw pointer; caller owns lifetime rules |
| configured input `const char *` | `Bytes` plus `#borrow` | Valid only for the duration of the call |
| configured `int` status plus one scalar `T*` or opaque `T**` output | `(Int, T)` plus generated C bridge | Explicit output parameter; no inferred cleanup |
| configured UTF-8 `char*` return | `String?` plus generated C bridge | Borrowed copy or copy and configured release |
| configured byte pointer and length | `Bytes` input or output plus generated C bridge | Explicit call/copy retention and capacity |
| borrowed byte pointer return and length function | `Bytes?` plus generated C bridge | Copied while valid; optional null discriminator |
| target-dependent scalar in config-v2 | `Int`, `UInt`, `Int64`, `UInt64`, or `Bool` | C bridge checks target range |
| configured multiple scalar/handle outputs | Public named result struct | Status preserved; fields initialized on failure |
| configured create/void-release handle | Managed resource and optional borrowed view | Close once, optional retain, finalizer; raw escape is explicit |
| other pointers, callbacks, variadics, by-value structs | none | Reported and skipped, or rejected in strict mode |

MoonBindgen emits auditable raw declarations alongside configured wrappers. Value structures and callbacks are later milestones; C++ and unprovable pointer lifetimes remain outside the supported surface.

## Auditable report v2

`report.json` uses `moonbindgen-report-v2`. It records the Clang version and target, referenced include files, declaration kind and source line, original C signature, emitted MoonBit declaration, status, stable reason code, and summary counts. Bridged declarations include `bridge: true`, and a generated C file sets `has_shim: true`. Existing v2 fields and reason codes are preserved.

For a config-v2 run, the report additionally records `config_schema` and each generated buffer/scalar policy. Config-v1 retains its previous report format.

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

The gate runs strict Native check/build/test, coverage analysis, two-run byte determinism, report schema assertions, include provenance, invalid-header rejection, three-artifact drift and rollback checks, generated C fixtures for strings, buffers, named outputs, resources, and the SQLite calls below. `scripts/verify_portable.py` runs all-target checks plus real Native calls on each CI host; the Linux job additionally compiles and runs generated examples with AddressSanitizer. This ASan gate retains MoonBit's bundled mimalloc allocator because the current prebuilt runtime links against it, so it does not promise ASan coverage of MoonBit-managed heap allocations.

`examples/sqlite` vendors the official SQLite 3.53.4 amalgamation. On Clang 23.1.1, MoonBindgen generates 133 functions and reports 165 skipped functions. It executes `SELECT 42`, then binds and reads an embedded-NUL BLOB, a zero-length BLOB, and SQL NULL through generated v2 bridges.

```powershell
moon run -q examples/sqlite
# SELECT 42 => 42
# SQLite BLOB => 3 bytes, empty, NULL
```

Exact upstream provenance, checksums, licensing, and the one comment-only local edit are recorded in [THIRD_PARTY.md](THIRD_PARTY.md).

## Release hygiene

`.moonignore` keeps fixtures, examples, scripts, CI configuration, tests, generated release assets, the local competition charter, and `submission/` out of the Mooncakes package. The SQLite amalgamation is marked vendored for GitHub language statistics. Run the full verification gate, `moon info`, `moon doc`, and `moon package --list` before publishing. `scripts/package-release.ps1` builds the stripped Windows CLI, creates deterministic release archives, and writes `SHA256SUMS.txt`.
