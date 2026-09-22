# Changelog

## 0.1.0 - 2026-09-22

- Generate conservative MoonBit Native C FFI declarations from Clang 23 JSON AST.
- Resolve scalar types, typedef chains, 32-bit enums, opaque struct pointers, and explicitly configured borrowed UTF-8 inputs.
- Emit deterministic bindings and a versioned `moonbindgen-report-v2` audit report.
- Provide exact filtering, renaming, restricted type overrides, strict unsupported-declaration handling, and drift checks.
- Verify generated declarations through Native ABI fixtures and SQLite 3.53.4 `SELECT 42`.
- Publish a Mooncakes library package and a Windows x64 CLI release artifact.
