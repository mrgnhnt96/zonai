# Raindrop is vendored under libs/raindrop. Its repository root is a separate Dart
# workspace; keeping that pubspec.yaml next to path dependencies into packages/*
# trips pub's workspace check for the zonai monorepo. Sparse-checkout only the
# packages/ tree so path deps like apps/zonai -> libs/raindrop/packages/raindrop work.
$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Submodule = Join-Path $Root "libs/raindrop"
$GitModules = Join-Path $Root ".gitmodules"

if (-not (Test-Path $GitModules) -or -not (Select-String -Path $GitModules -Pattern "libs/raindrop" -Quiet)) {
  Write-Error "libs/raindrop submodule is not configured in .gitmodules."
}

git -C $Root submodule update --init --recursive $Submodule
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

git -C $Submodule sparse-checkout init --no-cone
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

git -C $Submodule sparse-checkout set "/*" "!/pubspec.yaml" "!/.gitignore" "/packages/"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

git -C $Submodule sparse-checkout reapply
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Raindrop submodule: sparse checkout applied (packages/ only, root pubspec.yaml omitted)."
