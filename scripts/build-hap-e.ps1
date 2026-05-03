param(
  [string]$BuildMode = "debug",
  [string]$Product = "default",
  [string]$Module = "entry@default"
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\env-e.ps1"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$hvigor = "D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js"

if (-not (Test-Path $hvigor)) {
  throw "hvigorw.js was not found at $hvigor. Install DevEco Studio tooling outside C: and update this script."
}

Push-Location $repoRoot
try {
  node $hvigor --mode module -p "module=$Module" -p "product=$Product" -p "buildMode=$BuildMode" assembleHap --analyze=false
} finally {
  Pop-Location
}
