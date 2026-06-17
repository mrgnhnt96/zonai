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
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Executable
  $psi.Arguments = "serve --log verbose"
  $psi.WorkingDirectory = $PlaygroundDir
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true

  $serve = New-Object System.Diagnostics.Process
  $serve.StartInfo = $psi
  $serve.EnableRaisingEvents = $true
  $serve.add_OutputDataReceived({
    param($sender, $eventArgs)
    if ($null -ne $eventArgs.Data) {
      Write-Host $eventArgs.Data
    }
  })
  $serve.add_ErrorDataReceived({
    param($sender, $eventArgs)
    if ($null -ne $eventArgs.Data) {
      Write-Host $eventArgs.Data
    }
  })

  $null = $serve.Start()
  $serve.BeginOutputReadLine()
  $serve.BeginErrorReadLine()

  Start-Sleep -Seconds $ServeSeconds

  if ($serve.HasExited) {
    throw "serve exited before ${ServeSeconds}s (exit code $($serve.ExitCode))"
  }

  Stop-Process -Id $serve.Id -Force -ErrorAction SilentlyContinue
  $serve.WaitForExit()
  Write-Host "serve stayed running for ${ServeSeconds}s"
}
finally {
  Pop-Location
}
