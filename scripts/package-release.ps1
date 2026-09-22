param(
  [string]$Version = '0.1.0'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$buildRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot '_build'))
$stageRoot = [System.IO.Path]::GetFullPath((Join-Path $buildRoot 'release-stage'))
$distRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'dist'))

if (-not $stageRoot.StartsWith($buildRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Release staging directory escaped _build'
}

function Write-DeterministicZip {
  param(
    [string]$SourceDirectory,
    [string]$Destination
  )

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  if (Test-Path -LiteralPath $Destination) {
    Remove-Item -Force -LiteralPath $Destination
  }
  $sourceRoot = [System.IO.Path]::GetFullPath($SourceDirectory)
  $output = [System.IO.File]::Open($Destination, [System.IO.FileMode]::CreateNew)
  try {
    $archive = New-Object System.IO.Compression.ZipArchive(
      $output,
      [System.IO.Compression.ZipArchiveMode]::Create,
      $false
    )
    try {
      $fixedTimestamp = [System.DateTimeOffset]::Parse('1980-01-01T00:00:00Z')
      $files = Get-ChildItem -LiteralPath $sourceRoot -File -Recurse | Sort-Object FullName
      foreach ($file in $files) {
        $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\', '/').Replace('\', '/')
        $entry = $archive.CreateEntry($relative, [System.IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $fixedTimestamp
        $input = [System.IO.File]::OpenRead($file.FullName)
        try {
          $entryStream = $entry.Open()
          try {
            $input.CopyTo($entryStream)
          } finally {
            $entryStream.Dispose()
          }
        } finally {
          $input.Dispose()
        }
      }
    } finally {
      $archive.Dispose()
    }
  } finally {
    $output.Dispose()
  }
}

Push-Location $projectRoot
try {
  $moduleText = Get-Content -Raw -Encoding UTF8 -LiteralPath 'moon.mod'
  if (-not $moduleText.Contains("version = `"$Version`"")) {
    throw "moon.mod version does not match $Version"
  }

  & moon build --target native --release --strip cmd/main
  if ($LASTEXITCODE -ne 0) { throw 'Release CLI build failed' }
  & moon package
  if ($LASTEXITCODE -ne 0) { throw 'Mooncakes package build failed' }

  $executable = Join-Path $buildRoot 'native/release/build/cmd/main/main.exe'
  $package = Join-Path $buildRoot "publish/shop1111-moonbindgen-$Version.zip"
  if (-not (Test-Path -LiteralPath $executable)) { throw "Missing release executable: $executable" }
  if (-not (Test-Path -LiteralPath $package)) { throw "Missing Mooncakes package: $package" }
  $reportedVersion = (& $executable --version) -join "`n"
  if ($LASTEXITCODE -ne 0 -or $reportedVersion.Trim() -ne "moonbindgen $Version") {
    throw "Release executable version mismatch: $reportedVersion"
  }

  if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -Recurse -Force -LiteralPath $stageRoot
  }
  New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
  New-Item -ItemType Directory -Force -Path $distRoot | Out-Null
  Copy-Item -LiteralPath $executable -Destination (Join-Path $stageRoot 'moonbindgen.exe')
  foreach ($file in @('README.md', 'LICENSE', 'THIRD_PARTY.md', 'CHANGELOG.md', 'toolchain.json')) {
    Copy-Item -LiteralPath $file -Destination (Join-Path $stageRoot $file)
  }

  $binaryAsset = Join-Path $distRoot "moonbindgen-v$Version-windows-x86_64.zip"
  $packageAsset = Join-Path $distRoot "shop1111-moonbindgen-$Version.zip"
  $checksumAsset = Join-Path $distRoot 'SHA256SUMS.txt'
  Write-DeterministicZip -SourceDirectory $stageRoot -Destination $binaryAsset
  Copy-Item -Force -LiteralPath $package -Destination $packageAsset

  $checksumLines = @($binaryAsset, $packageAsset) | ForEach-Object {
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $_
    "$($hash.Hash.ToLowerInvariant())  $([System.IO.Path]::GetFileName($_))"
  }
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllLines($checksumAsset, $checksumLines, $utf8NoBom)

  Write-Output "Release assets written to $distRoot"
  Get-Item -LiteralPath $binaryAsset, $packageAsset, $checksumAsset |
    Select-Object Name, Length
  Get-Content -Encoding UTF8 -LiteralPath $checksumAsset
} finally {
  Pop-Location
}
