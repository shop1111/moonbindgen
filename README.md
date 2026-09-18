# MoonBindgen

MoonBindgen is a MoonBit Native CLI that asks Clang to parse a C header and emits raw MoonBit `extern "C"` bindings. It does not implement a C parser or infer pointer ownership.

## Requirements

- MoonBit with the Native target (developed with `moon 0.1.20260819`)
- Clang 23 (`23.1.1` is the tested build)
- Windows x64 for the current MVP

Clang is an external executable. Pass its path with `--clang` if it is not on `PATH`.

## Generate bindings

```powershell
moon run -q cmd/main -- generate fixtures/basic.h --out _build/basic --clang 'C:\Program Files\LLVM\bin\clang.exe'
```

The CLI writes `bindings.mbt` and `report.json`. To pass include paths or defines to Clang, put them after a second `--`:

```powershell
moon run -q cmd/main -- generate path/to/library.h --out path/to/moon-package --clang 'C:\Program Files\LLVM\bin\clang.exe' -- -Ipath/to/include -DSOME_OPTION=1
```

The report lists every function declaration from the selected header as generated or skipped, with a reason. The current mapper handles `int`, `unsigned int`, `float`, `double`, `void` returns, `long long`, `unsigned long long`, aliases of those types, 32-bit enum values, and pointers to struct typedefs represented as `#external` types. It skips variadic functions, strings, output pointers, callbacks, by-value structs, and other signatures without a verified direct ABI mapping. The generated layer is raw FFI: callers must manage C resources and respect the library's lifetime rules.

The CLI intentionally accepts only Clang 23. Clang's AST JSON format has no cross-version stability guarantee, so a new major release needs fixture verification before support is added.

## SQLite proof

`examples/sqlite` contains the official SQLite 3.53.4 amalgamation, the generated bindings, and a small handwritten shim for `sqlite3_open` and `sqlite3_prepare_v2` output pointers. The example then calls generated `sqlite3_step`, `sqlite3_column_int`, `sqlite3_finalize`, and `sqlite3_close` bindings to run `SELECT 42`:

```powershell
moon run -q examples/sqlite
```

Expected output: `SELECT 42 => 42`.

On the pinned header and Clang 23.1.1, 119 functions are generated and 179 are reported as skipped. The SQLite files came from [SQLite's official amalgamation download](https://www.sqlite.org/download.html), archive `sqlite-amalgamation-3530400.zip`, SHA3-256 `628a44cfe82c66aed1ccbbe85a562d2e33ebe64b3288981ed76285612227934e`. One trailing space was removed from a comment in `sqlite3.c`; its code is unchanged. SQLite is [dedicated to the public domain](https://sqlite.org/copyright.html); MoonBindgen's own code is MIT licensed.

## Verify

```powershell
./scripts/verify.ps1
```

This checks MoonBit compilation and tests, deterministic fixture output, unsupported and duplicate signatures, Clang diagnostics, SQLite coverage, and the actual query result.
