# Changelog

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
