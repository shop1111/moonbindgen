///|
fn usage() -> String {
  "Usage: moonbindgen generate <header> --out <dir> [--clang <exe>] [-- <clang arguments...>]"
}

///|
extern "C" fn native_exit(code : Int) -> Unit = "exit"

///|
fn die(message : String) -> Unit {
  println(message)
  native_exit(1)
}

///|
async fn capture(clang : String, args : Array[String]) -> (Int, String, String) {
  let (code, stdout, stderr) = @process.collect_output(clang, args) catch {
    _ => {
      die("Could not start Clang: " + clang)
      return (1, "", "")
    }
  }
  (code, stdout.text(), stderr.text())
}

///|
async fn main {
  let args = @env.args()
  if args.length() < 5 || args[1] != "generate" {
    die(usage())
  }
  let header = args[2]
  let mut out_dir = ""
  let mut clang = "clang"
  let clang_args : Array[String] = []
  let mut index = 3
  while index < args.length() {
    match args[index] {
      "--out" => {
        index += 1
        if index >= args.length() {
          die("--out needs a directory")
        }
        out_dir = args[index]
      }
      "--clang" => {
        index += 1
        if index >= args.length() {
          die("--clang needs an executable")
        }
        clang = args[index]
      }
      "--" => {
        index += 1
        while index < args.length() {
          clang_args.push(args[index])
          index += 1
        }
        break
      }
      other => die("Unexpected argument: " + other + "\n" + usage())
    }
    index += 1
  }
  if out_dir == "" {
    die("--out is required")
  }
  let (version_code, version_out, _) = capture(clang, ["--version"])
  if version_code != 0 || !version_out.contains("version 23.") {
    die("MoonBindgen requires Clang 23")
  }
  let absolute_header = @fs.realpath(header) catch {
    _ => {
      die("Header not found: " + header)
      return
    }
  }
  let command : Array[String] = [
    "-x", "c", "-std=c11", "-fsyntax-only", "-Xclang", "-ast-dump=json",
  ]
  for argument in clang_args {
    command.push(argument)
  }
  command.push(absolute_header)
  let (code, stdout, stderr) = capture(clang, command)
  if code != 0 {
    die("Clang failed:\n" + stderr)
  }
  let result = @lib.generate(stdout, absolute_header) catch {
    _ => {
      die("Could not interpret Clang 23 AST JSON")
      return
    }
  }
  if !@fs.exists(out_dir) {
    @fs.mkdir(out_dir, recursive=true)
  }
  @fs.write_file(out_dir + "/bindings.mbt", result.bindings)
  @fs.write_file(out_dir + "/report.json", result.report)
  println(
    "Generated " +
    result.generated.to_string() +
    " functions; skipped " +
    result.skipped.to_string(),
  )
}
