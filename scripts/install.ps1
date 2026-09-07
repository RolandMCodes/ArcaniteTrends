[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$WowRoot = (Join-Path ${env:ProgramFiles(x86)} 'World of Warcraft\_classic_era_'),
  [string]$SeedFile,
  [string]$BackupRoot
)

$ErrorActionPreference = 'Stop'
$addonRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourceDirectory = Join-Path $addonRoot 'ArcaniteTrends'
$runtimeFiles = @('ArcaniteTrends.toc', 'Core.lua', 'SeedData.lua', 'AuctionatorAdapter.lua', 'UI.lua', 'Main.lua')

if (Get-Process -Name WoWClassic, WoWClassicT, WoW -ErrorAction SilentlyContinue) {
  throw 'Close World of Warcraft before installing or updating ArcaniteTrends. The installer will not close it for you.'
}
$resolvedWowRoot = (Resolve-Path -LiteralPath $WowRoot).Path
if ((Split-Path -Leaf $resolvedWowRoot) -ne '_classic_era_') { throw 'Choose the _classic_era_ directory, not the retail or parent installation.' }
$addonsDirectory = (Resolve-Path -LiteralPath (Join-Path $resolvedWowRoot 'Interface\AddOns')).Path
$targetDirectory = [IO.Path]::GetFullPath((Join-Path $addonsDirectory 'ArcaniteTrends'))
if ((Split-Path -Parent $targetDirectory) -ne $addonsDirectory) { throw 'Addon destination escaped the AddOns directory.' }
foreach ($checkPath in @($resolvedWowRoot, $addonsDirectory, $targetDirectory)) {
  if ((Test-Path -LiteralPath $checkPath) -and ((Get-Item -LiteralPath $checkPath).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'Refusing installation through a junction or symbolic link. Choose a direct installation path.'
  }
}
if (-not (Test-Path -LiteralPath (Join-Path $addonsDirectory 'Auctionator\Auctionator.toc'))) { throw 'Auctionator is required in this Classic Era installation.' }
foreach ($name in $runtimeFiles) {
  if (-not (Test-Path -LiteralPath (Join-Path $sourceDirectory $name) -PathType Leaf)) { throw "Missing source file: $name" }
}
if (-not $SeedFile) {
  $defaultSeed = Join-Path $addonRoot 'private\SeedData.lua'
  if (Test-Path -LiteralPath $defaultSeed -PathType Leaf) { $SeedFile = $defaultSeed }
}
if ($SeedFile) {
  $SeedFile = (Resolve-Path -LiteralPath $SeedFile).Path
  if ((Get-Item -LiteralPath $SeedFile).Length -gt 5MB) { throw 'Seed file exceeds the supported size.' }
}
if (-not $BackupRoot) { $BackupRoot = Join-Path $addonRoot 'private\backups' }
$BackupRoot = [IO.Path]::GetFullPath($BackupRoot)
if ($BackupRoot.StartsWith($addonsDirectory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Backups must be stored outside the game AddOns directory.' }

if ($PSCmdlet.ShouldProcess($targetDirectory, 'Install ArcaniteTrends runtime files with a backup of any existing version')) {
  $existing = Test-Path -LiteralPath $targetDirectory
  if ($existing) {
    $backupDirectory = Join-Path $BackupRoot ('ArcaniteTrends-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
    # Copy, rather than move, the exact existing addon directory; nothing is deleted.
    Copy-Item -LiteralPath $targetDirectory -Destination $backupDirectory -Recurse
    Write-Output "Previous addon backed up to $backupDirectory"
  }
  New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
  foreach ($name in $runtimeFiles) {
    if ($name -eq 'SeedData.lua') {
      if ($SeedFile) { Copy-Item -LiteralPath $SeedFile -Destination (Join-Path $targetDirectory $name) -Force }
      elseif (-not (Test-Path -LiteralPath (Join-Path $targetDirectory $name))) {
        Copy-Item -LiteralPath (Join-Path $sourceDirectory $name) -Destination (Join-Path $targetDirectory $name)
      }
    } else {
      Copy-Item -LiteralPath (Join-Path $sourceDirectory $name) -Destination (Join-Path $targetDirectory $name) -Force
    }
  }
  Write-Output "Installed ArcaniteTrends at $targetDirectory"
  Write-Output 'Start Classic Era, enable Auctionator and ArcaniteTrends, and open /arc or the minimap button. In-game verification is still required.'
}
