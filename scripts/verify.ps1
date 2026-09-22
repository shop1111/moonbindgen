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
  if ($version.Output.Trim() -ne 'moonbindgen 0.1.0') { throw 'CLI version is not 0.1.0' }
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
  & moon fmt examples/native_fixture/bindings.mbt
  if ($LASTEXITCODE -ne 0) { throw 'Native ABI fixture formatting failed' }
  $nativeResult = & moon run -q examples/native_fixture
  if ($LASTEXITCODE -ne 0 -or ($nativeResult -join "`n").Trim() -ne 'Native ABI fixture => 42, 42, 10, 7') {
    throw 'Generated native ABI fixture failed'
  }

  & moon run -q cmd/main -- generate examples/sqlite/sqlite3.h --out examples/sqlite --clang $Clang
  if ($LASTEXITCODE -ne 0) { throw 'SQLite generation failed' }
  $sqliteReport = Get-Content -Raw -Encoding UTF8 -LiteralPath 'examples/sqlite/report.json' | ConvertFrom-Json
  if ($sqliteReport.generated -ne 128 -or $sqliteReport.skipped -ne 170) {
    throw 'SQLite coverage changed'
  }
  foreach ($name in @('sqlite3_step', 'sqlite3_column_int', 'sqlite3_finalize', 'sqlite3_close')) {
    if (-not ($sqliteReport.functions | Where-Object { $_.c_name -eq $name -and $_.status -eq 'generated' })) {
      throw "Required SQLite binding missing: $name"
    }
  }
  & moon run -q cmd/main -- generate examples/sqlite/sqlite3.h --out examples/sqlite --clang $Clang --check
  if ($LASTEXITCODE -ne 0) { throw 'SQLite generated artifacts drifted' }
  & moon fmt examples/sqlite/bindings.mbt
  if ($LASTEXITCODE -ne 0) { throw 'SQLite binding formatting failed' }
  $query = & moon run -q examples/sqlite
  if ($LASTEXITCODE -ne 0 -or ($query -join "`n").Trim() -ne 'SELECT 42 => 42') {
    throw 'SQLite query failed'
  }
  Write-Output 'MoonBindgen verification passed: fixture, diagnostics, SQLite SELECT 42.'
} finally {
  Pop-Location
}
