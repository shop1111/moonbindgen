///|
fn usage() -> String {
  (
    #|MoonBindgen 0.5.0
    #|Usage:
    #|  moonbindgen generate <header> --out <dir> [--clang <exe>] [--config <json>] [--check] [-- <clang arguments...>]
    #|
    #|Options:
    #|  --check          Compare all generated artifacts without writing
    #|  --config <json>  Read moonbindgen-config-v1 generation settings
    #|  --clang <exe>    Use the specified Clang 23 executable
    #|  --help           Show this help
    #|  --version        Show the MoonBindgen version
  )
}

///|
extern "C" fn native_exit(code : Int) -> Unit = "exit"

///|
fn die(code : Int, message : String) -> Unit {
  println(message)
  native_exit(code)
}

///|
async fn capture(clang : String, args : Array[String]) -> (Int, String, String) {
  let (code, stdout, stderr) = @process.collect_output(clang, args) catch {
    _ => {
      die(3, "Could not start Clang: " + clang)
      return (1, "", "")
    }
  }
  (code, stdout.text(), stderr.text())
}

///|
fn clang_metadata(text : String) -> @lib.ToolMetadata {
  let lines = text.split("\n").to_array()
  let version = if lines.length() == 0 {
    "unknown"
  } else {
    lines[0].trim().to_owned()
  }
  let mut target = "unknown"
  for line in lines {
    if line.has_prefix("Target: ") {
      target = line[8:].trim().to_owned()
    }
  }
  @lib.ToolMetadata::new(version, target)
}

///|
async fn safe_remove(path : String) -> Unit {
  if @fs.exists(path) {
    @fs.remove(path) catch {
      _ => ()
    }
  }
}

///|
async fn safe_rename(from : String, to : String) -> Bool {
  try @fs.rename(from, to, replace=true) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
async fn safe_write(path : String, content : String) -> Bool {
  try @fs.write_file(path, content) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
async fn replace_outputs(
  out_dir : String,
  bindings : String,
  report : String,
  shim : String?,
) -> Bool {
  if !@fs.exists(out_dir) {
    @fs.mkdir(out_dir, recursive=true) catch {
      _ => return false
    }
  }
  let paths = [
    out_dir + "/bindings.mbt",
    out_dir + "/report.json",
    out_dir + "/bindings_shim.c",
  ]
  let contents = [Some(bindings), Some(report), shim]
  let temps = paths.map(path => path + ".moonbindgen-tmp")
  let backups = paths.map(path => path + ".moonbindgen-backup")
  let backed_up = [false, false, false]
  let installed = [false, false, false]
  for index in 0..<3 {
    safe_remove(temps[index])
    safe_remove(backups[index])
  }
  for index in 0..<3 {
    match contents[index] {
      Some(value) if !safe_write(temps[index], value) => {
        for temp in temps {
          safe_remove(temp)
        }
        return false
      }
      _ => ()
    }
  }
  let mut success = true
  for index in 0..<3 {
    if @fs.exists(paths[index]) {
      if safe_rename(paths[index], backups[index]) {
        backed_up[index] = true
      } else {
        success = false
        break
      }
    }
  }
  if success {
    for index in 0..<3 {
      match contents[index] {
        Some(_) =>
          if safe_rename(temps[index], paths[index]) {
            installed[index] = true
          } else {
            success = false
            break
          }
        None => ()
      }
    }
  }
  if !success {
    for index in 0..<3 {
      if installed[index] {
        safe_remove(paths[index])
      }
      if backed_up[index] {
        ignore(safe_rename(backups[index], paths[index]))
      }
    }
  }
  for index in 0..<3 {
    safe_remove(temps[index])
    if success {
      safe_remove(backups[index])
    }
  }
  success
}

///|
async fn main {
  let args = @env.args()
  if args.length() == 2 && args[1] == "--help" {
    println(usage())
    return
  }
  if args.length() == 2 && args[1] == "--version" {
    println("moonbindgen 0.5.0")
    return
  }
  if args.length() >= 3 && args[1] == "generate" && args[2] == "--help" {
    println(usage())
    return
  }
  if args.length() < 5 || args[1] != "generate" {
    die(2, usage())
    return
  }
  let header = args[2]
  let mut out_dir = ""
  let mut clang = "clang"
  let mut config_path = ""
  let mut check_only = false
  let clang_args : Array[String] = []
  let mut index = 3
  while index < args.length() {
    match args[index] {
      "--out" => {
        index += 1
        if index >= args.length() {
          die(2, "--out needs a directory")
          return
        }
        out_dir = args[index]
      }
      "--clang" => {
        index += 1
        if index >= args.length() {
          die(2, "--clang needs an executable")
          return
        }
        clang = args[index]
      }
      "--config" => {
        index += 1
        if index >= args.length() {
          die(2, "--config needs a JSON file")
          return
        }
        config_path = args[index]
      }
      "--check" => check_only = true
      "--" => {
        index += 1
        while index < args.length() {
          clang_args.push(args[index])
          index += 1
        }
        break
      }
      other => {
        die(2, "Unexpected argument: " + other + "\n" + usage())
        return
      }
    }
    index += 1
  }
  if out_dir == "" {
    die(2, "--out is required")
    return
  }
  let (version_code, version_out, version_error) = capture(clang, ["--version"])
  if version_code != 0 || !version_out.contains("version 23.") {
    die(3, "MoonBindgen requires Clang 23\n" + version_error)
    return
  }
  let absolute_header = @fs.realpath(header) catch {
    _ => {
      die(2, "Header not found: " + header)
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
    die(3, "Clang failed:\n" + stderr)
    return
  }
  let config = if config_path == "" {
    @lib.GenerateConfig::default()
  } else {
    let text = @fs.read_file(config_path).text() catch {
      _ => {
        die(2, "Could not read configuration: " + config_path)
        return
      }
    }
    @lib.parse_config(text) catch {
      InvalidConfig(message) => {
        die(2, "Invalid configuration: " + message)
        return
      }
    }
  }
  let result = @lib.generate_with_metadata(
    stdout,
    absolute_header,
    config,
    clang_metadata(version_out),
  ) catch {
    Failure(message) => {
      die(4, "Generation rejected: " + message)
      return
    }
    _ => {
      die(4, "Could not interpret Clang 23 AST JSON")
      return
    }
  }
  let bindings_path = out_dir + "/bindings.mbt"
  let report_path = out_dir + "/report.json"
  let shim_path = out_dir + "/bindings_shim.c"
  if check_only {
    let current_bindings = @fs.read_file(bindings_path).text() catch {
      _ => {
        die(6, "Generated artifacts are missing: " + bindings_path)
        return
      }
    }
    let current_report = @fs.read_file(report_path).text() catch {
      _ => {
        die(6, "Generated artifacts are missing: " + report_path)
        return
      }
    }
    let shim_matches = match result.shim {
      Some(expected) => {
        let actual = @fs.read_file(shim_path).text() catch { _ => "" }
        @fs.exists(shim_path) && actual == expected
      }
      None => !@fs.exists(shim_path)
    }
    if current_bindings != result.bindings ||
      current_report != result.report ||
      !shim_matches {
      die(6, "Generated artifacts are out of date")
      return
    }
    println("Generated artifacts are up to date")
    return
  }
  if !replace_outputs(out_dir, result.bindings, result.report, result.shim) {
    die(5, "Could not safely replace generated artifacts in: " + out_dir)
    return
  }
  println(
    "Generated " +
    result.generated.to_string() +
    " functions; skipped " +
    result.skipped.to_string(),
  )
}
