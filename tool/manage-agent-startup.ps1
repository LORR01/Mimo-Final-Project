param(
  [ValidateSet('Install', 'Run', 'Status', 'Uninstall')]
  [string]$Mode = 'Status',
  [string]$AgentDirectory = ''
)
$ErrorActionPreference = 'Stop'
if (!$AgentDirectory) {
  $packageRoot = Split-Path -Parent $PSScriptRoot
  if (Test-Path -LiteralPath (Join-Path $packageRoot 'mimo-agent.exe')) { $AgentDirectory = $packageRoot }
  else { $AgentDirectory = Join-Path $packageRoot 'build/agent' }
}
$AgentDirectory = [IO.Path]::GetFullPath($AgentDirectory)
$agentExe = Join-Path $AgentDirectory 'mimo-agent.exe'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$taskName = "Mimo Agent - $sid"
$stateRoot = Join-Path $AgentDirectory '.local/agent'
$runnerPidFile = Join-Path $stateRoot 'startup-runner.pid'
$childFile = Join-Path $stateRoot 'startup-child.json'

function Stop-OwnedAgent {
  if (!(Test-Path -LiteralPath $childFile)) { return }
  $saved = Get-Content -LiteralPath $childFile -Raw | ConvertFrom-Json
  $owned = Get-Process -Id ([int]$saved.processId) -ErrorAction SilentlyContinue
  if ($owned) {
    # Both path and creation time must match; a reused PID is not our process.
    if ($owned.Path -ne $agentExe -or [string]$owned.StartTime.ToUniversalTime().Ticks -ne [string]$saved.startedUtcTicks) {
      throw 'Saved Agent identity does not match; refusing to stop an unrelated process.'
    }
    $owned.Kill()
    $owned.WaitForExit()
  }
  Remove-Item -LiteralPath $childFile -Force
}

if ($Mode -eq 'Status') {
  $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if (!$task) { Write-Output 'Mimo automatic startup is not installed.'; return }
  $task | Select-Object TaskName, State | Format-List
  Get-ScheduledTaskInfo -TaskName $taskName | Select-Object LastRunTime, LastTaskResult, NextRunTime | Format-List
  return
}

if ($Mode -eq 'Uninstall') {
  $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if ($task) {
    Stop-ScheduledTask -TaskName $taskName
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
  }
  Stop-OwnedAgent
  Write-Output 'Mimo automatic startup removed. Private data and Tailscale settings were preserved.'
  return
}

if (!(Test-Path -LiteralPath $agentExe -PathType Leaf)) { throw "Build or extract the PC Agent first: $agentExe" }
if ($Mode -eq 'Install') {
  $runnerScript = Join-Path $AgentDirectory 'tool/manage-agent-startup.ps1'
  if (!(Test-Path -LiteralPath $runnerScript)) { throw 'The Agent package is missing tool/manage-agent-startup.ps1.' }
  # Interactive user context is required for clipboard and SendInput; never use SYSTEM.
  $arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Mode Run -AgentDirectory "{1}"' -f $runnerScript, $AgentDirectory
  $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $arguments -WorkingDirectory $AgentDirectory
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $sid
  $principal = New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Limited
  $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
  $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if ($existing -and $existing.State -eq 'Running') { Stop-ScheduledTask -TaskName $taskName }
  Stop-OwnedAgent
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Mimo Agent in the signed-in desktop session; restarts on failure. No stored password.' -Force | Out-Null
  Start-ScheduledTask -TaskName $taskName
  Write-Output 'Mimo Agent automatic startup installed for this Windows user and started now.'
  Write-Output 'Sign in to Windows after restarting the PC. Do not move the Agent folder without reinstalling startup.'
  return
}

$mutex = [Threading.Mutex]::new($false, "Local\MimoAgentStartup-$sid")
$ownsMutex = $false
$child = $null
try {
  try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
  if (!$ownsMutex) { return }
  New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
  [IO.File]::WriteAllText($runnerPidFile, [string]$PID)
  $logRoot = Join-Path $stateRoot 'logs'
  New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
  $outLog = Join-Path $logRoot 'agent.stdout.log'
  $errLog = Join-Path $logRoot 'agent.stderr.log'
  while ($true) {
    # Leave existing listeners untouched; never kill an unknown process to take the port.
    $listener = New-Object Net.Sockets.TcpClient
    try { $listener.Connect('127.0.0.1', 8765); $occupied = $true }
    catch { $occupied = $false }
    finally { $listener.Dispose() }
    if ($occupied) { Start-Sleep -Seconds 10; continue }
    foreach ($log in @($outLog, $errLog)) {
      if (Test-Path -LiteralPath $log) { Move-Item -LiteralPath $log -Destination "$log.previous" -Force }
    }
    $child = Start-Process -FilePath $agentExe -ArgumentList @('--enable-commands', '--enable-sharing') -WorkingDirectory $AgentDirectory -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
    @{ processId = $child.Id; startedUtcTicks = [string]$child.StartTime.ToUniversalTime().Ticks } | ConvertTo-Json | Set-Content -LiteralPath $childFile -Encoding UTF8
    while (!$child.WaitForExit(10000)) { }
    $child.Dispose()
    $child = $null
    Remove-Item -LiteralPath $childFile -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 10
  }
} finally {
  if ($child) {
    if (!$child.HasExited) { $child.Kill() }
    $child.Dispose()
  }
  if ($ownsMutex) {
    Remove-Item -LiteralPath $runnerPidFile -Force -ErrorAction SilentlyContinue
    $mutex.ReleaseMutex()
  }
  $mutex.Dispose()
}
