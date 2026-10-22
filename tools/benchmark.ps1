#Requires -Version 7.0
param(
    [string]$GodotPath = 'E:\share\Godot_v4.7\Godot_v4.7-stable_win64_console.exe',
    [ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$Label = 'latest',
    [ValidateRange(1, 3)][int]$Rounds = 1
)

$ErrorActionPreference = 'Stop'
$benchmarkRoot = Split-Path -Parent $PSScriptRoot
$benchmarkLogs = Join-Path $benchmarkRoot '.local\validation'
$benchmarkAppData = Join-Path $benchmarkRoot '.local\appdata'
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Missing engine: $GodotPath" }
New-Item -ItemType Directory -Path $benchmarkLogs,$benchmarkAppData -Force | Out-Null
$benchmarkLog = Join-Path $benchmarkLogs "performance_$Label.log"
$benchmarkOutput = Join-Path $benchmarkLogs "performance_$Label.output.txt"
$benchmarkInfo = [System.Diagnostics.ProcessStartInfo]::new()
$benchmarkInfo.FileName = $GodotPath
$benchmarkInfo.WorkingDirectory = $benchmarkRoot
$benchmarkInfo.UseShellExecute = $false
$benchmarkInfo.CreateNoWindow = $true
$benchmarkInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$benchmarkInfo.RedirectStandardOutput = $true
$benchmarkInfo.RedirectStandardError = $true
$benchmarkInfo.Environment['APPDATA'] = $benchmarkAppData
# No fixed-fps, no Dummy audio, no disabled render loop: this measures real frames.
foreach ($benchmarkArgument in @('--path', (Join-Path $benchmarkRoot 'godot'), '--resolution', '1920x1080', '--disable-vsync', '--log-file', $benchmarkLog, '--script', 'res://tests/performance_benchmark.gd', '--', "--label=$Label", "--rounds=$Rounds")) {
    $benchmarkInfo.ArgumentList.Add($benchmarkArgument)
}
$benchmarkProcess = [System.Diagnostics.Process]::Start($benchmarkInfo)
$benchmarkStdout = $benchmarkProcess.StandardOutput.ReadToEndAsync()
$benchmarkStderr = $benchmarkProcess.StandardError.ReadToEndAsync()
$benchmarkDeadline = [DateTime]::UtcNow.AddSeconds(600)
while (-not $benchmarkProcess.WaitForExit(1000)) {
    if ([DateTime]::UtcNow -gt $benchmarkDeadline) {
        $benchmarkProcess.Kill($true)
        throw 'Benchmark exceeded ten-minute safety bound'
    }
}
$benchmarkText = $benchmarkStdout.GetAwaiter().GetResult() + $benchmarkStderr.GetAwaiter().GetResult()
Set-Content -LiteralPath $benchmarkOutput -Value $benchmarkText -Encoding utf8
$benchmarkEngineLog = if (Test-Path -LiteralPath $benchmarkLog) { Get-Content -LiteralPath $benchmarkLog -Raw } else { '' }
if ($benchmarkProcess.ExitCode -ne 0 -or ($benchmarkText + $benchmarkEngineLog) -match '(?im)^(SCRIPT ERROR:|ERROR:|FAIL:)') {
    Write-Output $benchmarkText
    throw "Benchmark failed; inspect $benchmarkOutput"
}
$benchmarkReportPath = Join-Path $benchmarkLogs "performance_$Label.json"
if (-not (Test-Path -LiteralPath $benchmarkReportPath)) { throw 'Benchmark did not produce its JSON report' }
$benchmarkReport = Get-Content -LiteralPath $benchmarkReportPath -Raw | ConvertFrom-Json
$benchmarkReport | Add-Member -NotePropertyName 'process_peak_working_set_mb' -NotePropertyValue ($benchmarkProcess.PeakWorkingSet64 / 1MB) -Force
$benchmarkReport | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $benchmarkReportPath -Encoding utf8
if ($benchmarkReport.failures -ne 0 -or $benchmarkReport.viewport[0] -ne 1920 -or $benchmarkReport.viewport[1] -ne 1080) { throw 'Benchmark resolution or functional checks failed' }
Write-Output "PASS: continuous 1080p benchmark; $benchmarkReportPath"
foreach ($benchmarkPhase in $benchmarkReport.phases.PSObject.Properties) {
    $phaseValue = $benchmarkPhase.Value
    Write-Output ("{0}: {1:N1} FPS, p95 {2:N2} ms, GPU p95 {3:N2} ms ({4} frames)" -f $benchmarkPhase.Name,$phaseValue.mean_fps,$phaseValue.wall_ms_p95,$phaseValue.gpu_ms_p95,$phaseValue.samples)
}
$benchmarkProcess.Dispose()
