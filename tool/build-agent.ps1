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
  [IO.File]::WriteAllText((Join-Path (Get-Location) 'build/agent/Start Mimo Agent.cmd'), "@echo off`r`ncd /d `"%~dp0`"`r`nmimo-agent.exe --enable-commands --enable-sharing`r`npause`r`n", [Text.UTF8Encoding]::new($false))
  Write-Output 'PC Agent ready in build/agent; start its launcher on the target PC.'
} finally { Pop-Location }
