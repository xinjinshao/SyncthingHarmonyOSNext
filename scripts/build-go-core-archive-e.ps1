param(
  [string]$WorkspaceRoot = "E:\Programming",
  [string]$SyncthingRoot = "E:\Programming\syncthing",
  [string]$OutputDir = "E:\Programming\SyncthingHarmonyOSNext\entry\src\main\libs\arm64-v8a"
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\env-e.ps1" -WorkspaceRoot $WorkspaceRoot

$ndk = $env:OHOS_NDK_HOME
if (-not (Test-Path $ndk)) {
  throw "OHOS_NDK_HOME is not valid: $ndk"
}

$arDir = Join-Path $WorkspaceRoot ".toolchains\ohos-bin"
New-Item -ItemType Directory -Force -Path $arDir | Out-Null
Copy-Item -Force (Join-Path $ndk "llvm\bin\llvm-ar.exe") (Join-Path $arDir "ar.exe")
Copy-Item -Force (Join-Path $ndk "llvm\bin\llvm-ranlib.exe") (Join-Path $arDir "ranlib.exe")

$env:PATH = $arDir + [IO.Path]::PathSeparator + $env:PATH

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Push-Location $SyncthingRoot
try {
  go run build.go assets
  if (-not $?) { throw "go run build.go assets failed" }

  $env:GOOS = "linux"
  $env:GOARCH = "arm64"
  $env:CGO_ENABLED = "1"
  $env:CC = "$ndk\llvm\bin\clang.exe -target aarch64-linux-ohos --sysroot=$ndk\sysroot -D__MUSL__"
  $env:CXX = "$ndk\llvm\bin\clang++.exe -target aarch64-linux-ohos --sysroot=$ndk\sysroot -D__MUSL__"
  $env:CGO_CFLAGS = ""
  $env:CGO_LDFLAGS = ""

  go build -trimpath -tags harmonyos -buildmode=c-archive `
    -asmflags=all="-tls=GD -D=TLS_GD" `
    -o (Join-Path $OutputDir "libsyncthingnative.a") `
    ./cmd/syncthing
  if (-not $?) { throw "go build c-archive failed" }
} finally {
  Pop-Location
}

Get-ChildItem -Path $OutputDir -Filter "libsyncthingnative.*" |
  Select-Object FullName, Length, LastWriteTime
