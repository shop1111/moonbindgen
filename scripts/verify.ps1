param(
  [string]$Clang = 'C:\Program Files\LLVM\bin\clang.exe'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Invoke-MoonBindgen {
  param([string[]]$CliArguments)

  $captured = & moon run -q cmd/main -- @CliArguments 2>&1
  [PSCustomObject]@{
    ExitCode = $LASTEXITCODE
    Output = ($captured -join [Environment]::NewLine)
  }
}

function Assert-ExitCode {
  param(
    [string]$Name,
    [object]$Result,
    [int]$Expected
  )

  if ($Result.ExitCode -ne $Expected) {
    throw "$Name returned $($Result.ExitCode), expected $Expected.`n$($Result.Output)"
  }
}

Push-Location $projectRoot
try {
  $expectedToolchain = Get-Content -Raw -Encoding UTF8 -LiteralPath 'toolchain.json' | ConvertFrom-Json
  $actualToolchain = (& moon version --all) -join "`n"
  if (-not $actualToolchain.Contains($expectedToolchain.moon)) { throw 'Unexpected Moon version' }
  if (-not $actualToolchain.Contains($expectedToolchain.moonc)) { throw 'Unexpected Moonc version' }
  $coreModule = Join-Path $env:USERPROFILE '.moon/lib/core/moon.mod'
  if (-not (Test-Path -LiteralPath $coreModule)) { throw 'MoonBit core manifest not found' }
  $coreManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $coreModule
  if (-not $coreManifest.Contains("version = `"$($expectedToolchain.core)`"")) {
    throw 'Unexpected Core version'
  }
  if (-not (Test-Path -LiteralPath $Clang)) { throw "Clang not found: $Clang" }
  $clangVersion = (& $Clang --version) -join "`n"
  if (-not $clangVersion.Contains("clang version $($expectedToolchain.clang)")) {
    throw "Unexpected Clang version: $clangVersion"
  }

  & moon check --target native --deny-warn --warn-list +73
  if ($LASTEXITCODE -ne 0) { throw 'MoonBit check failed' }
  & moon test --target native --deny-warn --enable-coverage
  if ($LASTEXITCODE -ne 0) { throw 'MoonBit tests failed' }
  & moon coverage analyze
  if ($LASTEXITCODE -ne 0) { throw 'Coverage analysis failed' }
  & moon build --target native --deny-warn
  if ($LASTEXITCODE -ne 0) { throw 'MoonBit build failed' }

  $help = Invoke-MoonBindgen @('--help')
  Assert-ExitCode 'CLI --help' $help 0
  if (-not $help.Output.Contains('Usage:')) { throw 'CLI help text is incomplete' }
  $version = Invoke-MoonBindgen @('--version')
  Assert-ExitCode 'CLI --version' $version 0
  if ($version.Output.Trim() -ne 'moonbindgen 0.5.0') { throw 'CLI version is not 0.5.0' }
  Assert-ExitCode 'CLI usage error' (Invoke-MoonBindgen @('generate')) 2

  New-Item -ItemType Directory -Force -Path '_build/verify' | Out-Null
  $missingClang = '_build/verify/missing-clang.exe'
  Assert-ExitCode 'CLI Clang error' (
    Invoke-MoonBindgen @('generate', 'fixtures/basic.h', '--out', '_build/verify/missing-clang', '--clang', $missingClang)
  ) 3

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  $strictConfig = '_build/verify/strict.config.json'
  [System.IO.File]::WriteAllText(
    $strictConfig,
    '{"schema":"moonbindgen-config-v1","unsupported_policy":"error"}',
    $utf8NoBom
  )
  Assert-ExitCode 'CLI strict generation error' (
    Invoke-MoonBindgen @('generate', 'fixtures/basic.h', '--out', '_build/verify/strict', '--clang', $Clang, '--config', $strictConfig)
  ) 4

  $notDirectory = '_build/verify/not-a-directory'
  [System.IO.File]::WriteAllText($notDirectory, 'file', $utf8NoBom)
  Assert-ExitCode 'CLI output I/O error' (
    Invoke-MoonBindgen @('generate', 'fixtures/basic.h', '--out', $notDirectory, '--clang', $Clang)
  ) 5
  Remove-Item -Force -LiteralPath $notDirectory

  $first = '_build/verify/basic-1'
  $second = '_build/verify/basic-2'
  & moon run -q cmd/main -- generate fixtures/basic.h --out $first --clang $Clang
  if ($LASTEXITCODE -ne 0) { throw 'First fixture generation failed' }
  & moon run -q cmd/main -- generate fixtures/basic.h --out $second --clang $Clang
  if ($LASTEXITCODE -ne 0) { throw 'Second fixture generation failed' }
  $a = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $first 'bindings.mbt')
  $b = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $second 'bindings.mbt')
  if ($a -cne $b) { throw 'Generated bindings are not deterministic' }
  if (Test-Path -LiteralPath (Join-Path $first 'bindings_shim.c')) {
    throw 'Unconfigured fixture unexpectedly generated a C shim'
  }
  $reportA = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $first 'report.json')
  $reportB = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $second 'report.json')
  if ($reportA -cne $reportB) { throw 'Generated reports are not deterministic' }
  $report = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $first 'report.json') | ConvertFrom-Json
  if ($report.schema -ne 'moonbindgen-report-v2') { throw 'Unexpected report schema' }
  if ($report.generated -ne 5 -or $report.skipped -ne 3) { throw 'Fixture coverage changed' }
  if (-not $a.Contains('pub type C_widget') -or -not $a.Contains('pub let c_mode_auto : Int = 2')) {
    throw 'Opaque type or enum value missing'
  }
  if (-not ($report.functions | Where-Object { $_.c_name -eq 'add' -and $_.reason_code -eq 'duplicate_declaration' })) {
    throw 'Duplicate declaration was not reported'
  }
  & moon run -q cmd/main -- generate fixtures/basic.h --out $first --clang $Clang --check
  if ($LASTEXITCODE -ne 0) { throw 'Generated artifact check failed' }
  [System.IO.File]::AppendAllText((Join-Path $first 'bindings.mbt'), "`n// drift", $utf8NoBom)
  Assert-ExitCode 'CLI generated artifact drift' (
    Invoke-MoonBindgen @('generate', 'fixtures/basic.h', '--out', $first, '--clang', $Clang, '--check')
  ) 6
  & moon run -q cmd/main -- generate fixtures/basic.h --out $first --clang $Clang
  if ($LASTEXITCODE -ne 0) { throw 'Fixture restoration after drift test failed' }
  [System.IO.File]::WriteAllText((Join-Path $first 'bindings_shim.c'), 'stale shim', $utf8NoBom)
  Assert-ExitCode 'CLI unexpected C shim drift' (
    Invoke-MoonBindgen @('generate', 'fixtures/basic.h', '--out', $first, '--clang', $Clang, '--check')
  ) 6
  & moon run -q cmd/main -- generate fixtures/basic.h --out $first --clang $Clang
  if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath (Join-Path $first 'bindings_shim.c'))) {
    throw 'Unneeded C shim was not removed'
  }

  $includeOutput = '_build/verify/include'
  & moon run -q cmd/main -- generate fixtures/with_include.h --out $includeOutput --clang $Clang -- -Ifixtures/includes
  if ($LASTEXITCODE -ne 0) { throw 'Clang include argument failed' }
  $includeReport = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $includeOutput 'report.json') | ConvertFrom-Json
  if ($includeReport.generated -ne 1 -or $includeReport.skipped -ne 0) {
    throw 'Typedef from an included header was not resolved'
  }

  $badOutput = '_build/verify/invalid-' + [Guid]::NewGuid().ToString('N')
  $invalidHeader = Invoke-MoonBindgen @('generate', 'fixtures/invalid.h', '--out', $badOutput, '--clang', $Clang)
  Assert-ExitCode 'CLI invalid-header Clang error' $invalidHeader 3
  if (Test-Path -LiteralPath $badOutput) {
    throw 'Invalid C header was accepted or created output'
  }

  & moon run -q cmd/main -- generate examples/native_fixture/fixture.h --out examples/native_fixture --clang $Clang --config examples/native_fixture/config.json
  if ($LASTEXITCODE -ne 0) { throw 'Native ABI fixture generation failed' }
  & moon run -q cmd/main -- generate examples/native_fixture/fixture.h --out examples/native_fixture --clang $Clang --config examples/native_fixture/config.json --check
  if ($LASTEXITCODE -ne 0) { throw 'Native ABI fixture drifted' }
  $nativeShim = 'examples/native_fixture/bindings_shim.c'
  $nativeShimText = Get-Content -Raw -Encoding UTF8 -LiteralPath $nativeShim
  if (-not $nativeShimText.Contains('abi_free_text(mbg_text)')) {
    throw 'Owned string release is missing from generated C shim'
  }
  $nativeBindingsText = Get-Content -Raw -Encoding UTF8 -LiteralPath 'examples/native_fixture/bindings.mbt'
  $nativeReportText = Get-Content -Raw -Encoding UTF8 -LiteralPath 'examples/native_fixture/report.json'
  $lockedShim = [System.IO.File]::Open($nativeShim, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
  try {
    Assert-ExitCode 'CLI third-artifact rollback' (
      Invoke-MoonBindgen @('generate', 'examples/native_fixture/fixture.h', '--out', 'examples/native_fixture', '--clang', $Clang, '--config', 'examples/native_fixture/config.json')
    ) 5
  } finally {
    $lockedShim.Dispose()
  }
  if ((Get-Content -Raw -Encoding UTF8 -LiteralPath 'examples/native_fixture/bindings.mbt') -cne $nativeBindingsText -or
      (Get-Content -Raw -Encoding UTF8 -LiteralPath 'examples/native_fixture/report.json') -cne $nativeReportText -or
      (Get-Content -Raw -Encoding UTF8 -LiteralPath $nativeShim) -cne $nativeShimText) {
    throw 'Failed three-artifact replacement changed output'
  }
  [System.IO.File]::AppendAllText($nativeShim, "`n// drift", $utf8NoBom)
  Assert-ExitCode 'CLI C shim drift' (
    Invoke-MoonBindgen @('generate', 'examples/native_fixture/fixture.h', '--out', 'examples/native_fixture', '--clang', $Clang, '--config', 'examples/native_fixture/config.json', '--check')
  ) 6
  & moon run -q cmd/main -- generate examples/native_fixture/fixture.h --out examples/native_fixture --clang $Clang --config examples/native_fixture/config.json
  if ($LASTEXITCODE -ne 0) { throw 'Native ABI fixture restoration failed' }
  & moon fmt examples/native_fixture/bindings.mbt
  if ($LASTEXITCODE -ne 0) { throw 'Native ABI fixture formatting failed' }
  $nativeResult = & moon run -q examples/native_fixture
  if ($LASTEXITCODE -ne 0 -or ($nativeResult -join "`n").Trim() -ne 'Native ABI fixture => 42, outputs and strings') {
    throw 'Generated native ABI fixture failed'
  }

  & moon run -q cmd/main -- generate examples/sqlite/sqlite3.h --out examples/sqlite --clang $Clang --config examples/sqlite/config.json
  if ($LASTEXITCODE -ne 0) { throw 'SQLite generation failed' }
  $sqliteReport = Get-Content -Raw -Encoding UTF8 -LiteralPath 'examples/sqlite/report.json' | ConvertFrom-Json
  if ($sqliteReport.generated -ne 133 -or $sqliteReport.skipped -ne 165) {
    throw 'SQLite coverage changed'
  }
  foreach ($name in @('sqlite3_open', 'sqlite3_prepare_v2', 'sqlite3_libversion', 'sqlite3_step', 'sqlite3_column_int', 'sqlite3_bind_blob', 'sqlite3_column_blob', 'sqlite3_finalize', 'sqlite3_close')) {
    if (-not ($sqliteReport.functions | Where-Object { $_.c_name -eq $name -and $_.status -eq 'generated' })) {
      throw "Required SQLite binding missing: $name"
    }
  }
  if (-not (Test-Path -LiteralPath 'examples/sqlite/bindings_shim.c')) {
    throw 'SQLite C shim was not generated'
  }
  & moon run -q cmd/main -- generate examples/sqlite/sqlite3.h --out examples/sqlite --clang $Clang --config examples/sqlite/config.json --check
  if ($LASTEXITCODE -ne 0) { throw 'SQLite generated artifacts drifted' }
  & moon fmt examples/sqlite/bindings.mbt
  if ($LASTEXITCODE -ne 0) { throw 'SQLite binding formatting failed' }
  $query = & moon run -q examples/sqlite
  if ($LASTEXITCODE -ne 0 -or ($query -join "`n").Trim() -ne "SELECT 42 => 42`nSQLite BLOB => 3 bytes, empty, NULL") {
    throw 'SQLite query failed'
  }

  & moon run -q cmd/main -- generate examples/buffer_fixture/fixture.h --out examples/buffer_fixture --clang $Clang --config examples/buffer_fixture/config.json
  if ($LASTEXITCODE -ne 0) { throw 'Buffer fixture generation failed' }
  & moon run -q cmd/main -- generate examples/buffer_fixture/fixture.h --out examples/buffer_fixture --clang $Clang --config examples/buffer_fixture/config.json --check
  if ($LASTEXITCODE -ne 0) { throw 'Buffer fixture drifted' }
  $bufferReport = Get-Content -Raw -Encoding UTF8 -LiteralPath 'examples/buffer_fixture/report.json' | ConvertFrom-Json
  if ($bufferReport.config_schema -ne 'moonbindgen-config-v2' -or $bufferReport.generated -ne 8) {
    throw 'Unexpected v2 buffer report'
  }
  $bufferResult = & moon run -q examples/buffer_fixture
  if ($LASTEXITCODE -ne 0 -or ($bufferResult -join "`n").Trim() -ne 'Buffer fixture => 42, zero, NULL, and invalid lengths') {
    throw 'Generated buffer ABI fixture failed'
  }
  & moon run -q cmd/main -- generate examples/multi_fixture/fixture.h --out examples/multi_fixture --clang $Clang --config examples/multi_fixture/config.json
  if ($LASTEXITCODE -ne 0) { throw 'Multi-output fixture generation failed' }
  & moon run -q cmd/main -- generate examples/multi_fixture/fixture.h --out examples/multi_fixture --clang $Clang --config examples/multi_fixture/config.json --check
  if ($LASTEXITCODE -ne 0) { throw 'Multi-output fixture drifted' }
  $multiReport = Get-Content -Raw -Encoding UTF8 -LiteralPath 'examples/multi_fixture/report.json' | ConvertFrom-Json
  if ($multiReport.config_schema -ne 'moonbindgen-config-v2' -or $multiReport.generated -ne 8 -or
      -not ($multiReport.functions | Where-Object { $_.c_name -eq 'make_pair' -and $_.policy -eq 'multi_output' }) -or
      -not ($multiReport.functions | Where-Object { $_.c_name -eq 'token_new' -and $_.policy -eq 'managed_resource' })) {
    throw 'Unexpected v2 resource report'
  }
  $multiResult = & moon run -q examples/multi_fixture
  if ($LASTEXITCODE -ne 0 -or ($multiResult -join "`n").Trim() -ne 'Multi-output and resource fixture => named fields, close once, retain') {
    throw 'Generated multi-output and resource fixture failed'
  }
  & moon run -q cmd/main -- generate examples/value_fixture/fixture.h --out examples/value_fixture --clang $Clang --config examples/value_fixture/config.json
  if ($LASTEXITCODE -ne 0) { throw 'Value fixture generation failed' }
  & moon run -q cmd/main -- generate examples/value_fixture/fixture.h --out examples/value_fixture --clang $Clang --config examples/value_fixture/config.json --check
  if ($LASTEXITCODE -ne 0) { throw 'Value fixture drifted' }
  $valueReport = Get-Content -Raw -Encoding UTF8 -LiteralPath 'examples/value_fixture/report.json' | ConvertFrom-Json
  if ($valueReport.generated -ne 5 -or $valueReport.skipped -ne 2 -or
      -not ($valueReport.functions | Where-Object { $_.c_name -eq 'point_add' -and $_.policy -eq 'value_struct' -and $_.abi_decision -eq 'compiled_field_bridge' }) -or
      -not ($valueReport.functions | Where-Object { $_.c_name -eq 'packed_bits_identity' -and $_.reason -like '*bit-field*' }) -or
      -not ($valueReport.functions | Where-Object { $_.c_name -eq 'flex_bytes_identity' -and $_.reason -like '*array*' })) {
    throw 'Unexpected value struct report'
  }
  $valueResult = & moon run -q examples/value_fixture
  if ($LASTEXITCODE -ne 0 -or ($valueResult -join "`n").Trim() -ne 'Value struct fixture => by-value arguments and return') {
    throw 'Generated value struct fixture failed'
  }
  & moon run -q cmd/main -- generate examples/callback_fixture/fixture.h --out examples/callback_fixture --clang $Clang --config examples/callback_fixture/config.json
  if ($LASTEXITCODE -ne 0) { throw 'Callback fixture generation failed' }
  & moon run -q cmd/main -- generate examples/callback_fixture/fixture.h --out examples/callback_fixture --clang $Clang --config examples/callback_fixture/config.json --check
  if ($LASTEXITCODE -ne 0) { throw 'Callback fixture drifted' }
  $callbackReport = Get-Content -Raw -Encoding UTF8 -LiteralPath 'examples/callback_fixture/report.json' | ConvertFrom-Json
  if ($callbackReport.generated -ne 4 -or $callbackReport.skipped -ne 1 -or
      -not ($callbackReport.functions | Where-Object { $_.c_name -eq 'call_once' -and $_.policy -eq 'call_callback' }) -or
      -not ($callbackReport.functions | Where-Object { $_.c_name -eq 'register_listener' -and $_.policy -eq 'persistent_callback' -and $_.bridge })) {
    throw 'Unexpected callback report'
  }
  $callbackResult = & moon run -q examples/callback_fixture
  if ($LASTEXITCODE -ne 0 -or ($callbackResult -join "`n").Trim() -ne 'Callback fixture => call, unregister once, finalizer, closure release') {
    throw 'Generated callback fixture failed'
  }
  Write-Output 'MoonBindgen verification passed: fixtures, callbacks, SQLite BLOB.'
} finally {
  Pop-Location
}
