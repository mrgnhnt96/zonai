param(
  [Parameter(Mandatory = $true)]
  [string]$Executable,

  [string]$PlaygroundDir = "apps/playground",

  [int]$ServeSeconds = 5
)

$ErrorActionPreference = "Stop"

$Executable = (Resolve-Path $Executable).Path
$PlaygroundDir = (Resolve-Path $PlaygroundDir).Path
Push-Location $PlaygroundDir

try {
  Write-Host "Verifying compile..."
  & $Executable compile
  if ($LASTEXITCODE -ne 0) {
    throw "compile failed with exit code $LASTEXITCODE"
  }
  Write-Host "compile succeeded"

  Write-Host "Verifying serve (must stay running for ${ServeSeconds}s)..."
  $serve = Start-Process `
    -FilePath $Executable `
    -ArgumentList "serve" `
    -WorkingDirectory $PlaygroundDir `
    -PassThru `
    -NoNewWindow

  Start-Sleep -Seconds $ServeSeconds

  if ($serve.HasExited) {
    throw "serve exited before ${ServeSeconds}s (exit code $($serve.ExitCode))"
  }

  Stop-Process -Id $serve.Id -Force -ErrorAction SilentlyContinue
  Write-Host "serve stayed running for ${ServeSeconds}s"
}
finally {
  Pop-Location
}
