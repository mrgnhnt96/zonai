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
  $logDir = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
  $serveLog = Join-Path $logDir "zonai-serve.log"
  $serveErrLog = Join-Path $logDir "zonai-serve.err.log"
  if (Test-Path $serveLog) { Remove-Item $serveLog -Force }
  if (Test-Path $serveErrLog) { Remove-Item $serveErrLog -Force }

  $serve = Start-Process `
    -FilePath $Executable `
    -ArgumentList "serve", "--log", "verbose" `
    -WorkingDirectory $PlaygroundDir `
    -PassThru `
    -RedirectStandardOutput $serveLog `
    -RedirectStandardError $serveErrLog

  Start-Sleep -Seconds $ServeSeconds

  if (Test-Path $serveLog) {
    Get-Content $serveLog | Write-Host
  }
  if (Test-Path $serveErrLog) {
    Get-Content $serveErrLog | Write-Host
  }

  if ($serve.HasExited) {
    throw "serve exited before ${ServeSeconds}s (exit code $($serve.ExitCode))"
  }

  Stop-Process -Id $serve.Id -Force -ErrorAction SilentlyContinue
  Write-Host "serve stayed running for ${ServeSeconds}s"
}
finally {
  Pop-Location
}
