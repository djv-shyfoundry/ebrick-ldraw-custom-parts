<#
.SYNOPSIS
  Auto-discovers canonical parts from real .col files and symlinks matching
  .conn/.col pairs to every decal-variant .dat file.

.DESCRIPTION
  Scans -ColDir for REAL (non-symlink) *.col files. Each one found (e.g.
  43722eb.col) is treated as a canonical base part. For each, looks for a
  matching canonical 43722eb.conn in -ConnDir, then symlinks BOTH the
  .conn and .col to every decal-variant *.dat file sharing that base name
  (43722ebtmp.dat, 43722eb000.dat, 43722eb001.dat, ...).

  No separate list of part names to maintain -- your collider folder IS
  the list.

.PARAMETER PartsDir
  Folder containing the *.dat variant files

.PARAMETER ConnDir
  Folder containing canonical *.conn files (and receiving symlinks)

.PARAMETER ColDir
  Folder containing canonical *.col files (and receiving symlinks)

.PARAMETER Clean
  Delete all existing SYMLINKS in ConnDir/ColDir before regenerating.
  Canonical (real) files are never touched.

.PARAMETER CleanOnly
  Delete all existing SYMLINKS in ConnDir/ColDir and exit -- does not
  scan for canonical parts or recreate any links. -PartsDir is not
  required when using this switch. Canonical (real) files are never
  touched.

.EXAMPLE
  .\Sync-ConnCol.ps1 -PartsDir .\parts -ConnDir .\connectivity -ColDir .\collider -Clean

.EXAMPLE
  .\Sync-ConnCol.ps1 -ConnDir .\connectivity -ColDir .\collider -CleanOnly

.NOTE
  Creating symlinks on Windows requires either Administrator privileges
  or Developer Mode enabled (Settings > Privacy & Security > For developers).
#>

# param(
    # [Parameter(Mandatory=$false)][string]$PartsDir,
    # [Parameter(Mandatory=$true)][string]$ConnDir,
    # [Parameter(Mandatory=$true)][string]$ColDir,
    # [switch]$Clean,
    # [switch]$CleanOnly
# )

param(
    [Parameter(Mandatory=$false)][string]$PartsDir=".\parts\",
    [Parameter(Mandatory=$false)][string]$ConnDir=".\connectivity\",
    [Parameter(Mandatory=$false)][string]$ColDir=".\collider\",
    [switch]$Clean,
    [switch]$CleanOnly
)

$ErrorActionPreference = "Stop"

function Test-IsSymlink($fileInfo) {
    return [bool]($fileInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
}

if (-not $CleanOnly -and [string]::IsNullOrWhiteSpace($PartsDir)) {
    throw "-PartsDir is required unless -CleanOnly is specified."
}

if ($Clean -or $CleanOnly) {
    Write-Host "Removing existing symlinks in $ConnDir and $ColDir ..."
    Get-ChildItem -Path $ConnDir -Filter *.conn | Where-Object { (Test-IsSymlink $_) -and ($_.Name -notlike "_*") } | ForEach-Object {
        Write-Host "Removing $($_.FullName)"
        Remove-Item $_.FullName -Force
    }
    Get-ChildItem -Path $ColDir -Filter *.col | Where-Object { (Test-IsSymlink $_) -and ($_.Name -notlike "_*") } | ForEach-Object {
        Write-Host "Removing $($_.FullName)"
        Remove-Item $_.FullName -Force
    }
}

if ($CleanOnly) {
    Write-Host "Done. All symlinks removed (CleanOnly mode - no relinking performed)."
    return
}

# Canonical col files = real (non-symlink), non-underscore-prefixed .col
# files, longest base name first so a more specific base claims its
# variants first.
$canonicalCols = Get-ChildItem -Path $ColDir -Filter *.col | Where-Object {
    (-not (Test-IsSymlink $_)) -and ($_.Name -notlike "_*")
}
$bases = $canonicalCols | Sort-Object { $_.BaseName.Length } -Descending

$claimed = @{}
$totalBases = 0
$totalLinks = 0

foreach ($col in $bases) {
    $baseName = $col.BaseName
    $canonicalConn = Join-Path $ConnDir "$baseName.conn"

    if (-not (Test-Path $canonicalConn)) {
        Write-Warning "No canonical conn file for '$baseName' (expected $canonicalConn) - skipping"
        continue
    }
    if ("$baseName.conn" -like "_*") {
        Write-Host "Skipping '$baseName' - canonical conn file is underscore-prefixed"
        continue
    }

    $totalBases++
    $matched = 0

    $datFiles = Get-ChildItem -Path $PartsDir -Filter "$baseName*.dat" -ErrorAction SilentlyContinue

    foreach ($dat in $datFiles) {
        $variant = [System.IO.Path]::GetFileNameWithoutExtension($dat.Name)

        if ($variant -eq $baseName) { continue }
        if ($claimed.ContainsKey($variant)) { continue }

        $targetConn = Join-Path $ConnDir "$variant.conn"
        $targetCol  = Join-Path $ColDir  "$variant.col"

        if (Test-Path $targetConn) { Remove-Item $targetConn -Force }
        if (Test-Path $targetCol)  { Remove-Item $targetCol -Force }

        New-Item -ItemType SymbolicLink -Path $targetConn -Target (Resolve-Path $canonicalConn) | Out-Null
        New-Item -ItemType SymbolicLink -Path $targetCol  -Target (Resolve-Path $col.FullName)   | Out-Null

        Write-Host "Linked  -> $targetConn"
        Write-Host "Linked  -> $targetCol"

        $claimed[$variant] = $true
        $matched++
        $totalLinks++
    }

    if ($matched -eq 0) {
        Write-Host "No variant dat files found for base '$baseName'"
    }
}

Write-Host "Done. Found $totalBases canonical part(s), created $totalLinks symlink(s)."