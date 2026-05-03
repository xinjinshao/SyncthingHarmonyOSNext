param(
  [string]$WorkspaceRoot = "E:\Programming",
  [string]$OpenHarmonySdkRoot = "E:\Programming\OpenHarmony\Sdk",
  [string]$DevEcoSdkRoot = "E:\Programming\HarmonyOS\Sdk"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$toolRoot = Join-Path $WorkspaceRoot ".toolchains"
$cacheRoot = Join-Path $WorkspaceRoot ".cache"
$tmpRoot = Join-Path $WorkspaceRoot "tmp"

$paths = @(
  $toolRoot,
  $cacheRoot,
  $tmpRoot,
  (Join-Path $toolRoot "go"),
  (Join-Path $toolRoot "go\env"),
  (Join-Path $toolRoot "go\path"),
  (Join-Path $toolRoot "go\path\pkg\mod"),
  (Join-Path $cacheRoot "go-build"),
  (Join-Path $cacheRoot "npm"),
  (Join-Path $cacheRoot "ohpm"),
  (Join-Path $repoRoot ".local\ohos-config")
)

foreach ($path in $paths) {
  New-Item -ItemType Directory -Force -Path $path | Out-Null
}

$env:GOPATH = Join-Path $toolRoot "go\path"
$env:GOROOT = Join-Path $toolRoot "go\sdk"
$env:GOMODCACHE = Join-Path $env:GOPATH "pkg\mod"
$env:GOCACHE = Join-Path $cacheRoot "go-build"
$env:GOENV = Join-Path $toolRoot "go\env\go.env"
$env:GOTMPDIR = $tmpRoot
$env:TMP = $tmpRoot
$env:TEMP = $tmpRoot
$env:NPM_CONFIG_CACHE = Join-Path $cacheRoot "npm"
$env:OHPM_HOME = Join-Path $cacheRoot "ohpm"
$env:XDG_CACHE_HOME = $cacheRoot

if (Test-Path (Join-Path $env:GOROOT "bin\go.exe")) {
  $env:PATH = (Join-Path $env:GOROOT "bin") + [IO.Path]::PathSeparator + $env:PATH
}

if (Test-Path $DevEcoSdkRoot) {
  $env:DEVECO_SDK_HOME = $DevEcoSdkRoot
} elseif (Test-Path $OpenHarmonySdkRoot) {
  $env:DEVECO_SDK_HOME = $OpenHarmonySdkRoot
}

if (Test-Path $OpenHarmonySdkRoot) {
  $sdkVersionDir = Get-ChildItem -Path $OpenHarmonySdkRoot -Directory |
    Where-Object { $_.Name -match "^\d+$" } |
    Sort-Object { [int]$_.Name } -Descending |
    Select-Object -First 1

  if ($sdkVersionDir -ne $null) {
    $nativeDir = Join-Path $sdkVersionDir.FullName "native"
    if (Test-Path $nativeDir) {
      $env:OHOS_NDK_HOME = $nativeDir
    }
  }
}

$signingSource = Join-Path $env:USERPROFILE ".ohos\config"
$signingTarget = Join-Path $repoRoot ".local\ohos-config"
if ((Test-Path $signingSource) -and -not (Get-ChildItem -Path $signingTarget -Filter "default_SyncthingHarmonyOSNext*.p12" -ErrorAction SilentlyContinue)) {
  Copy-Item -Force -Path (Join-Path $signingSource "default_SyncthingHarmonyOSNext*") -Destination $signingTarget
}
if ((Test-Path (Join-Path $signingSource "material")) -and -not (Test-Path (Join-Path $signingTarget "material"))) {
  Copy-Item -Recurse -Force -Path (Join-Path $signingSource "material") -Destination $signingTarget
}

Write-Host "E-drive build environment is active."
Write-Host "GOPATH=$env:GOPATH"
Write-Host "GOROOT=$env:GOROOT"
Write-Host "GOMODCACHE=$env:GOMODCACHE"
Write-Host "GOCACHE=$env:GOCACHE"
Write-Host "TEMP=$env:TEMP"
Write-Host "DEVECO_SDK_HOME=$env:DEVECO_SDK_HOME"
Write-Host "OHOS_NDK_HOME=$env:OHOS_NDK_HOME"
