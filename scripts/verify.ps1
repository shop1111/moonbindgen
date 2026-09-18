param(
  [string]$Clang = 'C:\Program Files\LLVM\bin\clang.exe'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $projectRoot
try {
  & moon check --target native --deny-warn
  if ($LASTEXITCODE -ne 0) { throw 'MoonBit check failed' }
  & moon test --target native
  if ($LASTEXITCODE -ne 0) { throw 'MoonBit tests failed' }

  $first = '_build/verify/basic-1'
  $second = '_build/verify/basic-2'
  & moon run -q cmd/main -- generate fixtures/basic.h --out $first --clang $Clang
  if ($LASTEXITCODE -ne 0) { throw 'First fixture generation failed' }
  & moon run -q cmd/main -- generate fixtures/basic.h --out $second --clang $Clang
  if ($LASTEXITCODE -ne 0) { throw 'Second fixture generation failed' }
  $a = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $first 'bindings.mbt')
  $b = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $second 'bindings.mbt')
  if ($a -cne $b) { throw 'Generated bindings are not deterministic' }
  $report = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $first 'report.json') | ConvertFrom-Json
  if ($report.generated -ne 5 -or $report.skipped -ne 3) { throw 'Fixture coverage changed' }
  if (-not $a.Contains('pub type C_widget') -or -not $a.Contains('pub let c_mode_auto : Int = 2')) {
    throw 'Opaque type or enum value missing'
  }
  if (-not ($report.functions | Where-Object { $_.name -eq 'add' -and $_.reason -eq 'duplicate declaration' })) {
    throw 'Duplicate declaration was not reported'
  }

  $includeOutput = '_build/verify/include'
  & moon run -q cmd/main -- generate fixtures/with_include.h --out $includeOutput --clang $Clang -- -Ifixtures/includes
  if ($LASTEXITCODE -ne 0) { throw 'Clang include argument failed' }
  $includeReport = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $includeOutput 'report.json') | ConvertFrom-Json
  if ($includeReport.generated -ne 1 -or $includeReport.skipped -ne 0) {
    throw 'Typedef from an included header was not resolved'
  }

  $badOutput = '_build/verify/invalid-' + [Guid]::NewGuid().ToString('N')
  & moon run -q cmd/main -- generate fixtures/invalid.h --out $badOutput --clang $Clang | Out-Null
  if ($LASTEXITCODE -eq 0 -or (Test-Path -LiteralPath $badOutput)) {
    throw 'Invalid C header was accepted or created output'
  }

  & moon run -q cmd/main -- generate examples/sqlite/sqlite3.h --out examples/sqlite --clang $Clang
  if ($LASTEXITCODE -ne 0) { throw 'SQLite generation failed' }
  $sqliteReport = Get-Content -Raw -Encoding UTF8 -LiteralPath 'examples/sqlite/report.json' | ConvertFrom-Json
  if ($sqliteReport.generated -ne 119 -or $sqliteReport.skipped -ne 179) {
    throw 'SQLite coverage changed'
  }
  foreach ($name in @('sqlite3_step', 'sqlite3_column_int', 'sqlite3_finalize', 'sqlite3_close')) {
    if (-not ($sqliteReport.functions | Where-Object { $_.name -eq $name -and $_.status -eq 'generated' })) {
      throw "Required SQLite binding missing: $name"
    }
  }
  $query = & moon run -q examples/sqlite
  if ($LASTEXITCODE -ne 0 -or ($query -join "`n").Trim() -ne 'SELECT 42 => 42') {
    throw 'SQLite query failed'
  }
  & moon fmt --check
  if ($LASTEXITCODE -ne 0) { throw 'Generated MoonBit source is not formatted' }
  Write-Output 'MoonBindgen verification passed: fixture, diagnostics, SQLite SELECT 42.'
} finally {
  Pop-Location
}
