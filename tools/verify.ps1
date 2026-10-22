#Requires -Version 7.0
param(
    [string]$GodotPath = 'E:\share\Godot_v4.7\Godot_v4.7-stable_win64_console.exe',
    [switch]$HeadlessOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$gamePath = Join-Path $projectRoot 'godot'
$outputPath = Join-Path $projectRoot '.local\validation'
$appDataPath = Join-Path $projectRoot '.local\appdata'
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found: $GodotPath. Supply -GodotPath explicitly."
}
New-Item -ItemType Directory -Path $outputPath, $appDataPath -Force | Out-Null

# Validate every explicit res:// path, including the configured main scene.
$referenceCount = 0
Get-ChildItem -LiteralPath $gamePath -Recurse -File |
    Where-Object { $_.Extension -in '.godot', '.gd', '.tscn', '.tres' -and $_.FullName -notmatch '[\\/]\.godot[\\/]' } |
    ForEach-Object {
        $source = Get-Content -LiteralPath $_.FullName -Raw
        foreach ($match in [regex]::Matches($source, 'res://[^"\s]+')) {
            $target = Join-Path $gamePath $match.Value.Substring(6)
            if (-not (Test-Path -LiteralPath $target)) { throw "Missing reference in $($_.FullName): $($match.Value)" }
            $referenceCount++
        }
    }
Write-Output "PASS: $referenceCount resource references resolve"

function Invoke-GodotCheck {
    param([string]$Name, [string[]]$EngineArguments)
    $logPath = Join-Path $outputPath "$Name.log"
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GodotPath
    $startInfo.WorkingDirectory = $projectRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Environment['APPDATA'] = $appDataPath
    foreach ($argument in (@('--path', $gamePath, '--log-file', $logPath, '--max-fps', '0') + $EngineArguments)) {
        $startInfo.ArgumentList.Add($argument)
    }
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(60000)) {
        $process.Kill($true)
        throw "$Name timed out after 60 seconds"
    }
    $output = $stdoutTask.GetAwaiter().GetResult() + $stderrTask.GetAwaiter().GetResult()
    Set-Content -LiteralPath (Join-Path $outputPath "$Name.output.txt") -Value $output -Encoding utf8
    $engineLog = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw } else { '' }
    if ($process.ExitCode -ne 0 -or ($output + $engineLog) -match '(?im)^(SCRIPT ERROR:|ERROR:|FAIL:)') {
        Write-Output $output
        throw "$Name failed (exit $($process.ExitCode)); inspect $outputPath"
    }
    Write-Output "PASS: $Name (exit $($process.ExitCode))"
    if ($Name -in 'input-physics', 'combat-rules', 'combat-integration', 'enemy-rules', 'enemy-behavior', 'enemy-integration', 'blessing-rules', 'room-flow', 'room-integration', 'guardian-behavior', 'full-run-integration', 'art-headless', 'art-rendering', 'audio-feedback', 'vfx-headless', 'vfx-rendering') {
        $output -split "`n" | Where-Object { $_ -match 'RESULT:|Vulkan.*Forward' } | Write-Output
    }
    $process.Dispose()
}

Invoke-GodotCheck -Name 'import' -EngineArguments @('--headless', '--editor', '--import')
Invoke-GodotCheck -Name 'main-headless' -EngineArguments @('--headless', '--fixed-fps', '60', '--script', 'res://tests/main_scene_smoke_test.gd')
Invoke-GodotCheck -Name 'combat-rules' -EngineArguments @('--headless', '--script', 'res://tests/combat_rules_test.gd')
Invoke-GodotCheck -Name 'enemy-rules' -EngineArguments @('--headless', '--fixed-fps', '60', '--script', 'res://tests/enemy_rules_test.gd')
Invoke-GodotCheck -Name 'enemy-behavior' -EngineArguments @('--headless', '--fixed-fps', '60', '--script', 'res://tests/enemy_behavior_test.gd')
Invoke-GodotCheck -Name 'blessing-rules' -EngineArguments @('--headless', '--script', 'res://tests/blessing_rules_test.gd')
Invoke-GodotCheck -Name 'room-flow' -EngineArguments @('--headless', '--fixed-fps', '60', '--script', 'res://tests/room_flow_test.gd')
Invoke-GodotCheck -Name 'guardian-behavior' -EngineArguments @('--headless', '--fixed-fps', '60', '--script', 'res://tests/guardian_behavior_test.gd')
Invoke-GodotCheck -Name 'art-headless' -EngineArguments @('--headless', '--fixed-fps', '60', '--script', 'res://tests/art_validation_test.gd')
Invoke-GodotCheck -Name 'audio-feedback' -EngineArguments @('--headless', '--fixed-fps', '60', '--audio-driver', 'Dummy', '--script', 'res://tests/audio_feedback_test.gd')
Invoke-GodotCheck -Name 'vfx-headless' -EngineArguments @('--headless', '--fixed-fps', '60', '--audio-driver', 'Dummy', '--script', 'res://tests/vfx_feedback_test.gd')
if ($HeadlessOnly) {
    Write-Output 'SKIP: graphical input/physics suite and Forward+ rendering; requires a desktop session.'
} else {
    Invoke-GodotCheck -Name 'main-window' -EngineArguments @('--fixed-fps', '60', '--disable-vsync', '--audio-driver', 'Dummy', '--script', 'res://tests/main_scene_smoke_test.gd')
    Invoke-GodotCheck -Name 'art-rendering' -EngineArguments @('--fixed-fps', '60', '--disable-vsync', '--disable-render-loop', '--audio-driver', 'Dummy', '--script', 'res://tests/art_validation_test.gd')
    Invoke-GodotCheck -Name 'vfx-rendering' -EngineArguments @('--fixed-fps', '60', '--disable-vsync', '--disable-render-loop', '--audio-driver', 'Dummy', '--script', 'res://tests/vfx_feedback_test.gd')
    Invoke-GodotCheck -Name 'input-physics' -EngineArguments @('--fixed-fps', '60', '--disable-vsync', '--disable-render-loop', '--audio-driver', 'Dummy', '--script', '../tools/smoke_test.gd')
    Invoke-GodotCheck -Name 'combat-integration' -EngineArguments @('--fixed-fps', '60', '--disable-vsync', '--disable-render-loop', '--audio-driver', 'Dummy', '--script', 'res://tests/combat_integration_test.gd')
    Invoke-GodotCheck -Name 'enemy-integration' -EngineArguments @('--fixed-fps', '60', '--disable-vsync', '--disable-render-loop', '--audio-driver', 'Dummy', '--script', 'res://tests/enemy_integration_test.gd')
    Invoke-GodotCheck -Name 'room-integration' -EngineArguments @('--fixed-fps', '60', '--disable-vsync', '--disable-render-loop', '--audio-driver', 'Dummy', '--script', 'res://tests/room_integration_test.gd')
    Invoke-GodotCheck -Name 'full-run-integration' -EngineArguments @('--fixed-fps', '60', '--disable-vsync', '--disable-render-loop', '--audio-driver', 'Dummy', '--script', 'res://tests/full_run_integration_test.gd')
}
