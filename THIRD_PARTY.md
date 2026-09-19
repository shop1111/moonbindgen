# Third-party material

## SQLite 3.53.4

The Native proof in `examples/sqlite` vendors `sqlite3.c` and `sqlite3.h` from the official `sqlite-amalgamation-3530400.zip` archive published at <https://www.sqlite.org/download.html>.

- Upstream archive SHA3-256: `628a44cfe82c66aed1ccbbe85a562d2e33ebe64b3288981ed76285612227934e`
- Vendored `sqlite3.c` SHA-256: `6747327b19a634e38c616784877b9ba8952b33a1e9903379c65f766c6cda9187`
- Vendored `sqlite3.h` SHA-256: `919e7f2e8ed1d8f56ac17b412b8971c76aa5d1a879752cc6058f75e7d5910e1d`
- License status: SQLite is dedicated to the public domain; see <https://sqlite.org/copyright.html>.
- Local change: one trailing space was removed from a comment in `sqlite3.c`; executable code is unchanged.

The handwritten `examples/sqlite/shim.c` is MoonBindgen project code under MIT. It demonstrates the boundary for output pointers and is not copied from SQLite.

## Clang and LLVM

MoonBindgen invokes a separately installed Clang executable and does not redistribute LLVM. The verified workflow pins LLVM 23.1.1. LLVM licensing is documented at <https://llvm.org/docs/DeveloperPolicy.html#new-llvm-project-license-framework>.
