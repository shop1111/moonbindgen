// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "shop1111/moonbindgen"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/shop1111/moonbindgen"

license = "MIT"

keywords = [ "ffi", "bindings", "clang", "code-generation" ]

preferred_target = "native"

description = "Generate MoonBit native C FFI declarations from C headers with Clang."

import {
  "moonbitlang/async@0.21.0",
}
