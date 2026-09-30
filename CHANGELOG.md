# Changelog

## 0.6.0 - 2026-09-30

- Generate direct closed `FuncRef` calls for explicitly call-scoped scalar callbacks.
- Generate same-thread persistent callback registrations for `void (*)(void*, int)` and a declared `void unregister(void*)` contract. Closing and finalization unregister once and release the retained closure; raw declarations remain available for manual use.
- Reject missing or malformed callback contracts, cross-thread policies, and unsupported callback ABIs. Exercise call, registration, repeated close, finalization, and deterministic generation in a Native fixture, including Linux AddressSanitizer.

## 0.5.0 - 2026-09-29

- Lower complete C value structs with scalar fields through generated C field bridges for by-value arguments and results. Target compilation checks direct scalar field widths; padding and alignment stay entirely on the C side.
- Follow typedef chains to supported structs, reject bit-fields and flexible or fixed arrays with auditable reasons, and record the v2 ABI decision without changing v1 report fields.
- Exercise by-value construction, two-struct calls, scalar return, typedef aliases, and unsupported record shapes in a generated Native fixture on Windows and Linux, including Linux AddressSanitizer.

## 0.4.0 - 2026-09-29

- Generate named result structs for multiple configured scalar and opaque-handle outputs, including target-dependent scalar conversion and preserved C status on failure.
- Generate managed opaque resources when a create function, exact-handle `void` release, and optional `void` retain function are declared. Closing is idempotent, retained instances release independently, and the last reference invokes a C finalizer.
- Generate borrowed same-handle views that keep the managed owner alive and reject access after explicit close. A release function that can fail remains a raw binding and is marked for manual management in the report.
- Exercise named outputs, failed calls, duplicate close, retain, finalizer, and borrowed-view lifetime in a generated Native fixture on Windows and Linux, including Linux AddressSanitizer.

## 0.3.0 - 2026-09-29

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
