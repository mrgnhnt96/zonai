param(
  [Parameter(Mandatory = $true)]
  [string]$Executable,

  [string]$PlaygroundDir = "apps/playground",

  [int]$ServeSeconds = 5
)

$ErrorActionPreference = "Stop"

$HealthUrls = @(
  "http://127.0.0.1:8080/health",
  "http://[::1]:8080/health",
  "http://localhost:8080/health"
)

function Test-ServerHealth {
  foreach ($url in $HealthUrls) {
    try {
      $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2
      if ($response.StatusCode -eq 200) {
        Write-Host "Health check passed: $url"
        return $true
      }
    } catch {
      continue
    }
  }
  return $false
}

function Write-ServeLogs {
  param(
    [string]$OutPath,
    [string]$ErrPath
  )

  if (Test-Path $OutPath) {
    Get-Content $OutPath | Write-Host
  }
  if (Test-Path $ErrPath) {
    Get-Content $ErrPath | Write-Host
  }
}

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
    -ArgumentList "serve", "--log", "verbose", "--no-version-check" `
    -WorkingDirectory $PlaygroundDir `
    -PassThru `
    -RedirectStandardOutput $serveLog `
    -RedirectStandardError $serveErrLog

  $deadline = (Get-Date).AddSeconds($ServeSeconds)
  $healthOk = $false

  Write-Host "Waiting for /health..."
  while ((Get-Date) -lt $deadline) {
    if ($serve.HasExited) {
      Write-ServeLogs -OutPath $serveLog -ErrPath $serveErrLog
      throw "serve exited before health check (exit code $($serve.ExitCode))"
    }

    if (Test-ServerHealth) {
      $healthOk = $true
      break
    }

    Start-Sleep -Milliseconds 500
  }

  if (-not $healthOk) {
    Write-ServeLogs -OutPath $serveLog -ErrPath $serveErrLog
    Stop-Process -Id $serve.Id -Force -ErrorAction SilentlyContinue
    throw "health check failed within ${ServeSeconds}s"
  }

  $remaining = ($deadline - (Get-Date)).TotalSeconds
  if ($remaining -gt 0) {
    Start-Sleep -Seconds $remaining
  }

  if ($serve.HasExited) {
    Write-ServeLogs -OutPath $serveLog -ErrPath $serveErrLog
    throw "serve exited before ${ServeSeconds}s (exit code $($serve.ExitCode))"
  }

  Stop-Process -Id $serve.Id -Force -ErrorAction SilentlyContinue
  $serve.WaitForExit()
  Start-Sleep -Milliseconds 250
  Write-ServeLogs -OutPath $serveLog -ErrPath $serveErrLog
  Write-Host "serve stayed running for ${ServeSeconds}s"
}
finally {
  Pop-Location
}
