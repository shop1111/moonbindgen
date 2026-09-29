# Changelog

## 0.3.0 - pending verification

- Add `moonbindgen-config-v2` with position-based input, output, and borrowed-return byte-buffer policies. Invalid signatures and conflicting policies fail with explicit diagnostics.
- Generate length-checked C bridges for buffers and target-dependent `short`, `long`, `size_t`, `ptrdiff_t`, and `_Bool` scalars.
- Exercise embedded NUL, empty, NULL, negative-capacity, and invalid borrowed-buffer cases in a Native fixture; bind and read SQLite BLOB values while retaining `SELECT 42`.
- Add Linux Clang 23.1.1 regeneration, real Native calls, and AddressSanitizer gates. Keep config-v1 output behavior and report shape.

## 0.2.0 - 2026-09-28

- Generate opt-in C bridges and MoonBit wrappers for one scalar or opaque-handle output pointer with an `int` status.
- Copy borrowed or explicitly owned UTF-8 C string returns into `String?`, calling a declared compatible release function for owned values.
- Check and replace the optional C shim alongside bindings and reports, with rollback on output failure.
- Run the SQLite `SELECT 42` proof through generated open and prepare bindings; cover null, failure, decoding, and release paths in the Native fixture.

## 0.1.0 - 2026-09-22

- Generate conservative MoonBit Native C FFI declarations from Clang 23 JSON AST.
- Resolve scalar types, typedef chains, 32-bit enums, opaque struct pointers, and explicitly configured borrowed UTF-8 inputs.
- Emit deterministic bindings and a versioned `moonbindgen-report-v2` audit report.
- Provide exact filtering, renaming, restricted type overrides, strict unsupported-declaration handling, and drift checks.
- Verify generated declarations through Native ABI fixtures and SQLite 3.53.4 `SELECT 42`.
- Publish a Mooncakes library package and a Windows x64 CLI release artifact.
