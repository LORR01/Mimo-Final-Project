param([string]$DartPath = 'dart')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  New-Item -ItemType Directory -Force build/agent/tool/agent | Out-Null
  & $DartPath compile exe tool/mimo_agent.dart -o build/agent/mimo-agent.exe
  if ($LASTEXITCODE -ne 0) { throw 'Agent compilation failed' }
  Copy-Item -LiteralPath tool/agent/windows_metrics.ps1 -Destination build/agent/tool/agent/windows_metrics.ps1
  if (Test-Path build/web) { New-Item -ItemType Directory -Force build/agent/build/web | Out-Null; Get-ChildItem -LiteralPath build/web -Force | Where-Object { $_.Name -ne 'downloads' } | Copy-Item -Destination build/agent/build/web -Recurse -Force }
  Copy-Item -LiteralPath docs/PC_AGENT_SETUP.md -Destination build/agent/README.md
  Copy-Item -LiteralPath tool/manage-agent-startup.ps1 -Destination build/agent/tool/manage-agent-startup.ps1
  Copy-Item -LiteralPath tool/check-agent.ps1 -Destination build/agent/tool/check-agent.ps1
  foreach ($entry in @(@('Enable Mimo Auto Start.cmd', 'Install'), @('Disable Mimo Auto Start.cmd', 'Uninstall'))) {
    $launcher = "@echo off`r`ncd /d `"%~dp0`"`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"tool\manage-agent-startup.ps1`" -Mode $($entry[1]) -AgentDirectory `"%~dp0.`"`r`npause`r`n"
    [IO.File]::WriteAllText((Join-Path (Get-Location) "build/agent/$($entry[0])"), $launcher, [Text.UTF8Encoding]::new($false))
  }
  $checkLauncher = "@echo off`r`ncd /d `"%~dp0`"`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"tool\check-agent.ps1`" -AgentDirectory `"%~dp0.`"`r`npause`r`n"
  [IO.File]::WriteAllText((Join-Path (Get-Location) 'build/agent/Check Mimo Connection.cmd'), $checkLauncher, [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path (Get-Location) 'build/agent/Start Mimo Agent.cmd'), "@echo off`r`ncd /d `"%~dp0`"`r`nmimo-agent.exe --enable-commands --enable-sharing`r`npause`r`n", [Text.UTF8Encoding]::new($false))
  Write-Output 'PC Agent ready in build/agent; start its launcher on the target PC.'
} finally { Pop-Location }
