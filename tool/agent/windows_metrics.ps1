$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$readings = @{}
$availability = @{}
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'"
if ($null -ne $cpu.PercentProcessorTime) { $readings.cpu = [double]$cpu.PercentProcessorTime }
$readings.ramTotal = [math]::Round([double]$os.TotalVisibleMemorySize / 1MB, 2)
$readings.ramUsed = [math]::Round(([double]$os.TotalVisibleMemorySize - [double]$os.FreePhysicalMemory) / 1MB, 2)
try {
  $engines = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine)
  if ($engines.Count -gt 0) {
    # Sum processes within the same physical engine, then use the busiest engine.
    # Avoid summing unrelated GPU engines into a fictitious utilization percentage.
    $groups = $engines | Group-Object { $_.Name -replace '^pid_\d+_', '' }
    $loads = @($groups | ForEach-Object { ($_.Group | Measure-Object UtilizationPercentage -Sum).Sum })
    $readings.gpu = [math]::Min(100, [double](($loads | Measure-Object -Maximum).Maximum))
  } else { $availability.gpu = 'Windows ไม่ส่ง GPU engine counter' }
} catch { $availability.gpu = 'อ่าน GPU engine counter ไม่ได้' }
foreach ($namespace in @('root/LibreHardwareMonitor','root/OpenHardwareMonitor')) {
  try {
    $sensors = @(Get-CimInstance -Namespace $namespace -ClassName Sensor -Filter "SensorType='Temperature'")
    $cpuSensors = @($sensors | Where-Object { $_.Identifier -match '/(intelcpu|amdcpu)/' -and $_.Value -gt 0 })
    $gpuSensors = @($sensors | Where-Object { $_.Identifier -match '/(nvidiagpu|amdgpu|intelgpu)/' -and $_.Value -gt 0 })
    if ($cpuSensors.Count -gt 0) { $readings.cpuTemp = [double](($cpuSensors | Measure-Object Value -Maximum).Maximum) }
    if ($gpuSensors.Count -gt 0) { $readings.gpuTemp = [double](($gpuSensors | Measure-Object Value -Maximum).Maximum) }
  } catch { }
}
$primaryGpu = $null
  try {
    $nvidia = Join-Path $env:WINDIR 'System32/nvidia-smi.exe'
    if (Test-Path -LiteralPath $nvidia) {
      $rows = @(& $nvidia --query-gpu=name,utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>$null | ConvertFrom-Csv -Header name,load,temp | Where-Object { $_.load -match '^\s*\d+(\.\d+)?\s*$' -and $_.temp -match '^\s*\d+(\.\d+)?\s*$' })
      if ($LASTEXITCODE -eq 0 -and $rows.Count -gt 0) {
        $chosen = $rows | Sort-Object { [double]$_.load } -Descending | Select-Object -First 1
        $readings.gpuTemp = [double]$chosen.temp
        $readings.gpu = [double]$chosen.load
        $primaryGpu = $chosen.name.Trim()
        $availability.Remove('gpu')
      }
    }
  } catch { }
if (!$readings.ContainsKey('cpuTemp')) { $availability.cpuTemp = 'เปิด LibreHardwareMonitor ด้วยสิทธิ์ผู้ดูแลเพื่ออ่าน CPU temperature; Agent ไม่ติดตั้งไดรเวอร์หรือปิดระบบป้องกัน Windows ให้อัตโนมัติ' }
if (!$readings.ContainsKey('gpuTemp')) { $availability.gpuTemp = 'ไม่มี GPU temperature sensor จาก LibreHardwareMonitor/OpenHardwareMonitor' }
$cpuName = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
$gpuNames = @(Get-CimInstance Win32_VideoController | ForEach-Object Name)
@{ readings=$readings; availability=$availability; hardware=@{cpu=$cpuName;gpu=$gpuNames;primaryGpu=$primaryGpu;os=$os.Caption}; sampledAt=[DateTimeOffset]::Now.ToString('o') } | ConvertTo-Json -Depth 6 -Compress
