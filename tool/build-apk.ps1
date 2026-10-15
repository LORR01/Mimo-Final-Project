param([string]$AgentUrl = '', [string]$FlutterPath = '', [string]$AndroidSdk = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not ('MimoBuildAlias' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
public static class MimoBuildAlias {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern uint QueryDosDevice(string name, StringBuilder output, int size);
  public static string Resolve(string path) {
    foreach (var drive in DriveInfo.GetDrives()) {
      var output = new StringBuilder(4096);
      if (QueryDosDevice(drive.Name.TrimEnd('\\'), output, output.Capacity) == 0) continue;
      var target = output.ToString();
      if (target.StartsWith(@"\??\") && String.Equals(target.Substring(4).TrimEnd('\\'), Path.GetFullPath(path).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)) return drive.Name;
    }
    return path;
  }
}
'@
}
function Resolve-BuildAlias([string]$Path) {
  return [MimoBuildAlias]::Resolve($Path)
}
if (!$FlutterPath) {
  $installed = Get-Command flutter.bat -ErrorAction SilentlyContinue
  if ($installed) { $FlutterPath = $installed.Source }
  else { $FlutterPath = Join-Path (Resolve-BuildAlias (Join-Path (Split-Path $projectRoot -Parent) '.tooling/flutter')) 'bin/flutter.bat' }
}
if (!(Test-Path -LiteralPath $FlutterPath)) { throw 'Install Flutter or pass -FlutterPath' }
if (!$AndroidSdk) {
  $localSdk = Join-Path (Split-Path $projectRoot -Parent) '.tooling/android-sdk'
  if (Test-Path -LiteralPath $localSdk) { $AndroidSdk = Resolve-BuildAlias $localSdk }
  elseif ($env:ANDROID_HOME) { $AndroidSdk = $env:ANDROID_HOME }
  else { $AndroidSdk = Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
}
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
if (!$env:JAVA_HOME -and (Test-Path 'C:/Program Files/Android/Android Studio/jbr')) { $env:JAVA_HOME = 'C:/Program Files/Android/Android Studio/jbr' }
if (!$AgentUrl) {
  $tailscale = Join-Path $env:ProgramFiles 'Tailscale/tailscale.exe'
  if (Test-Path -LiteralPath $tailscale) {
    $serve = (& $tailscale serve status --json) | ConvertFrom-Json
    if ($serve.Web) {
      foreach ($entry in $serve.Web.PSObject.Properties) {
        if ($entry.Value.Handlers.'/'.Proxy -eq 'http://127.0.0.1:8765') { $AgentUrl = "https://$($entry.Name)"; break }
      }
    }
  }
}
$parsed = $null
if (!$AgentUrl -or ![Uri]::TryCreate($AgentUrl,[UriKind]::Absolute,[ref]$parsed) -or $parsed.Scheme -ne 'https' -or $parsed.UserInfo -or $parsed.Query -or $parsed.Fragment) { throw 'Provide -AgentUrl https://your-pc.your-tailnet.ts.net:8443 (no passwords/tokens)' }
Push-Location (Resolve-BuildAlias $projectRoot)
try {
  & $FlutterPath pub get
  if ($LASTEXITCODE -ne 0) { throw 'pub get failed' }
  $dart = Join-Path (Split-Path $FlutterPath -Parent) 'dart.bat'
  & $dart format --output=none --set-exit-if-changed lib test tool
  if ($LASTEXITCODE -ne 0) { throw 'Format check failed; APK was not built' }
  & $FlutterPath analyze --no-pub
  if ($LASTEXITCODE -ne 0) { throw 'Analyze failed; APK was not built' }
  & $FlutterPath test --no-pub
  if ($LASTEXITCODE -ne 0) { throw 'Tests failed; APK was not built' }
  & $FlutterPath build apk --debug --no-pub "--dart-define=MIMO_AGENT_URL=$AgentUrl"
  if ($LASTEXITCODE -ne 0) { throw 'APK build failed' }
  New-Item -ItemType Directory -Force build/deliverables | Out-Null
  Copy-Item -LiteralPath build/app/outputs/flutter-apk/app-debug.apk -Destination build/deliverables/Mimo-testing.apk
  Get-FileHash build/deliverables/Mimo-testing.apk -Algorithm SHA256 | Format-List
  Write-Host 'Ready: build/deliverables/Mimo-testing.apk (debug-signed test installation)'
} finally { Pop-Location }
