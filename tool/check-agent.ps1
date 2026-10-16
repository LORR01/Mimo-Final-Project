param([string]$AgentDirectory = '')
$ErrorActionPreference = 'Stop'
if (!$AgentDirectory) {
  $packageRoot = Split-Path -Parent $PSScriptRoot
  if (Test-Path -LiteralPath (Join-Path $packageRoot 'mimo-agent.exe')) { $AgentDirectory = $packageRoot }
  else { $AgentDirectory = Join-Path $packageRoot 'build/agent' }
}
$AgentDirectory = [IO.Path]::GetFullPath($AgentDirectory)
$script:failed = $false
function Write-Check([string]$Level, [string]$Message) {
  Write-Output "[$Level] $Message"
  if ($Level -eq 'FAIL') { $script:failed = $true }
}

Write-Output 'Mimo connection check (read-only; no tokens, clipboard or device inventory printed)'
foreach ($relative in @('mimo-agent.exe', 'tool/agent/windows_metrics.ps1', 'tool/manage-agent-startup.ps1')) {
  if (Test-Path -LiteralPath (Join-Path $AgentDirectory $relative)) { Write-Check 'PASS' "Package file: $relative" }
  else { Write-Check 'FAIL' "Missing $relative. Build or extract the complete PC Agent package." }
}
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
try {
  $task = Get-ScheduledTask -TaskName "Mimo Agent - $sid" -ErrorAction SilentlyContinue
  if (!$task) { Write-Check 'WARN' 'Auto Start is not installed for this user. Run Enable Mimo Auto Start.cmd.' }
  else {
    if ($task.State -eq 'Running') { Write-Check 'PASS' 'Auto Start task is running.' }
    else { Write-Check 'WARN' "Auto Start state: $($task.State). Run Enable Mimo Auto Start.cmd to start/repair it." }
    $runnerScript = Join-Path $AgentDirectory 'tool/manage-agent-startup.ps1'
    if (!$task.Actions -or !$task.Actions[0].Arguments.Contains('"' + $runnerScript + '"')) {
      Write-Check 'FAIL' 'Auto Start points to another folder. Disable it from the old package, then enable it from this package.'
    }
  }
} catch { Write-Check 'WARN' 'Cannot inspect Task Scheduler. Check under the Windows account that installed Auto Start.' }
try {
  $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/v1/health' -TimeoutSec 5
  if ($health.service -ne 'mimo-agent' -or $health.protocol -ne 1) { throw 'Unexpected listener' }
  Write-Check 'PASS' 'Local Mimo Agent responds on port 8765.'
  if ($health.readOnly) { Write-Check 'WARN' 'Agent is read-only. Auto Start enables commands and sharing.' }
} catch { Write-Check 'FAIL' 'Local Agent is unavailable or port 8765 belongs to another service. Enable Auto Start and inspect private Agent logs; do not stop unknown processes.' }

$tailscale = Join-Path $env:ProgramFiles 'Tailscale/tailscale.exe'
if (!(Test-Path -LiteralPath $tailscale)) {
  Write-Check 'FAIL' 'Tailscale is not installed in its standard location. Install the official Windows app.'
} else {
  try {
    $rawStatus = & $tailscale status --json 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read Tailscale status' }
    $status = $rawStatus | ConvertFrom-Json
    if ($status.BackendState -eq 'Running' -and $status.Self.Online) { Write-Check 'PASS' 'Tailscale is connected.' }
    else { Write-Check 'FAIL' 'Tailscale is disconnected or needs login. Open Tailscale and reconnect.' }
    $rawServe = & $tailscale serve status --json 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read Serve status' }
    $serve = $rawServe | ConvertFrom-Json
    $expectedHost = ([string]$status.Self.DNSName).TrimEnd('.')
    $expectedKey = $expectedHost + ':8443'
    $mapping = $null
    if ($serve.Web) { $mapping = $serve.Web.PSObject.Properties | Where-Object Name -eq $expectedKey | Select-Object -First 1 }
    if (!$mapping -or $mapping.Value.Handlers.'/'.Proxy -ne 'http://127.0.0.1:8765') {
      Write-Check 'FAIL' 'Missing Mimo HTTPS proxy on 8443. Inspect tailscale serve status before configuring it; preserve other services.'
    } else {
      Write-Check 'PASS' 'Tailscale Serve maps HTTPS 8443 to the local Agent.'
      try {
        $remote = Invoke-RestMethod -Uri ("https://{0}:8443/v1/health" -f $expectedHost) -TimeoutSec 15
        if ($remote.service -ne 'mimo-agent' -or $remote.protocol -ne 1) { throw 'Unexpected service' }
        Write-Check 'PASS' 'Tailscale HTTPS reaches Mimo with certificate validation.'
      } catch { Write-Check 'FAIL' 'HTTPS is unreachable. Check connectivity, DNS, Serve/HTTPS approval and tailnet access policy.' }
    }
  } catch { Write-Check 'FAIL' 'Cannot read Tailscale CLI status. Check its service/login; access-denied errors may require a terminal elevated as the SAME Windows user.' }
}
Write-Output 'This checks this PC, not Android login or phone-to-PC permissions. Logs may contain private data; do not post them unredacted.'
if ($script:failed) { exit 1 }
exit 0
