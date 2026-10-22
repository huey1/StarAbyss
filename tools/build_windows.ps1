#Requires -Version 7.0
param(
    [string]$GodotPath = 'E:\share\Godot_v4.7\Godot_v4.7-stable_win64_console.exe',
    [switch]$PackOnly,
    [switch]$SkipSmoke
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$gamePath = Join-Path $projectRoot 'godot'
$templatePath = Join-Path $projectRoot '.local/export_templates/4.7.stable/windows_release_x86_64.exe'
$archivePath = Join-Path $projectRoot '.local/export_templates/cache/Godot_v4.7-stable_export_templates.tpz'
$expectedArchiveHash = '9714459dc071907c0f3d5f17d608faf69e7cda21331fc5d39c4503ffa4e99eec'
$buildRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'builds/windows'))
$packagePath = [IO.Path]::GetFullPath((Join-Path $buildRoot 'star_abyss_windows_x64'))
$diagnosticsPath = Join-Path $projectRoot '.local/export-diagnostics'
$appDataPath = Join-Path $projectRoot '.local/appdata'
$exePath = Join-Path $packagePath 'StarAbyss.exe'
$pckPath = Join-Path $packagePath 'StarAbyss.pck'
$zipPath = Join-Path $buildRoot 'star_abyss_windows_x64.zip'

if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot editor not found: $GodotPath"
}
if (-not $PackOnly -and -not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    throw "Missing Godot 4.7 release template: $templatePath. No download is performed; see docs/BUILD_WINDOWS.md."
}
if (-not $PackOnly -and (Test-Path -LiteralPath $archivePath)) {
    $archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($archiveHash -ne $expectedArchiveHash) { throw 'Official export-template archive SHA256 mismatch.' }
}
New-Item -ItemType Directory -Path $buildRoot, $packagePath, $diagnosticsPath, $appDataPath -Force | Out-Null

function Invoke-EngineStage {
    param([string]$Name, [string]$Executable, [string[]]$Arguments, [string]$WorkingDirectory = $gamePath)
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Environment['APPDATA'] = $appDataPath
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(60000)) {
        $process.Kill($true)
        throw "$Name timed out after 60 seconds"
    }
    $output = $stdoutTask.GetAwaiter().GetResult() + $stderrTask.GetAwaiter().GetResult()
    $exitCode = $process.ExitCode
    $process.Dispose()
    Set-Content -LiteralPath (Join-Path $diagnosticsPath "$Name.output.txt") -Value $output -Encoding utf8
    $engineLog = ''
    $engineLogIndex = [Array]::IndexOf($Arguments, '--log-file')
    if ($engineLogIndex -ge 0 -and $engineLogIndex + 1 -lt $Arguments.Count -and (Test-Path -LiteralPath $Arguments[$engineLogIndex + 1])) {
        $engineLog = Get-Content -LiteralPath $Arguments[$engineLogIndex + 1] -Raw
    }
    if ($exitCode -ne 0 -or ($output + $engineLog) -match '(?im)^\s*(SCRIPT ERROR:|SHADER ERROR:|ERROR:|FAIL:|WARNING:)') {
        throw "$Name failed (exit $exitCode):`n$output`n$engineLog"
    }
    return $output
}

$editorVersion = (Invoke-EngineStage -Name 'editor-version' -Executable $GodotPath -Arguments @('--version')).Trim()
if ($editorVersion -notmatch '^4\.7\.stable\.') { throw "Expected Godot 4.7 stable, got $editorVersion" }
if (-not $PackOnly) {
    $templateVersion = (Invoke-EngineStage -Name 'template-version' -Executable $templatePath -Arguments @('--version')).Trim()
    if ($templateVersion -ne $editorVersion) {
        throw "Template/editor versions differ: $templateVersion versus $editorVersion"
    }
}

$exportLog = Join-Path $diagnosticsPath 'export.log'
$exportArguments = @('--headless', '--path', $gamePath, '--log-file', $exportLog)
if ($PackOnly) {
    $exportArguments += @('--export-pack', 'Windows Desktop', $pckPath)
} else {
    $exportArguments += @('--export-release', 'Windows Desktop', $exePath)
}
$null = Invoke-EngineStage -Name 'export' -Executable $GodotPath -Arguments $exportArguments
if (-not (Test-Path -LiteralPath $pckPath -PathType Leaf)) { throw 'Export did not produce a PCK.' }
Write-Output "PASS: PCK exported ($((Get-Item -LiteralPath $pckPath).Length) bytes)"
if ($PackOnly) {
    Get-FileHash -LiteralPath $pckPath -Algorithm SHA256 | Format-List
    return
}
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { throw 'Export did not produce a release executable.' }

# Read engine-provided notices, rather than hard-coding incomplete third-party text.
$noticesScript = Join-Path $diagnosticsPath 'write_engine_notices.gd'
@'
extends SceneTree

func _initialize() -> void:
    var destination: String = OS.get_cmdline_user_args()[0]
    var license_file: FileAccess = FileAccess.open(destination.path_join("GODOT_LICENSE.txt"), FileAccess.WRITE)
    if license_file == null:
        push_error("Cannot write Godot license notice")
        quit(1)
        return
    license_file.store_string(Engine.get_license_text())
    license_file.close()
    var third_party: FileAccess = FileAccess.open(destination.path_join("THIRD_PARTY_NOTICES.json"), FileAccess.WRITE)
    if third_party == null:
        push_error("Cannot write third-party notices")
        quit(1)
        return
    third_party.store_string(JSON.stringify({"copyright": Engine.get_copyright_info(), "licenses": Engine.get_license_info()}, "\t"))
    third_party.close()
    quit(0)
'@ | Set-Content -LiteralPath $noticesScript -Encoding utf8
$null = Invoke-EngineStage -Name 'engine-notices' -Executable $GodotPath -Arguments @('--headless', '--path', $gamePath, '--script', $noticesScript, '--', $packagePath)

$packageReadme = @'
星渊遗迹 / Star Abyss — Windows x64 试玩包

启动：完整解压后双击 StarAbyss.exe。请将 StarAbyss.pck 保持在同一目录。
本包无需安装 Godot 或 Blender。使用支持 Vulkan 的 Windows x64 PC。

WASD 移动；鼠标转镜头；左键三段剑击；E 星刃斩；Shift 闪避；Space 跳跃；Esc 暂停。
从主菜单进入两间普通房与第三间 Boss 房。普通房清场后必须选择祝福，再穿过北侧出口。
暂停、胜利和失败界面可重新开始或返回主菜单；重新开始会清空本局进度。

首次游玩请确认游戏音量与预警可读性，完整走完一局后分别尝试重开和返回主菜单。
自动化检查不能代替人工的手感、画面和音效评价。

引擎许可见 GODOT_LICENSE.txt；引擎第三方组件通知见 THIRD_PARTY_NOTICES.json。
SHA256SUMS.txt 可用于核对解压后的文件完整性。
'@
Set-Content -LiteralPath (Join-Path $packagePath '试玩说明.txt') -Value $packageReadme -Encoding utf8

if (-not $SkipSmoke) {
    $smokeScript = Join-Path $gamePath 'tests/export_smoke_test.gd'
    $screenshotPath = Join-Path $diagnosticsPath 'package_gameplay.png'
    # Official release templates disable --main-pack/--script path overrides.
    # Validate the final data pack with the identical-version editor runtime, then
    # launch the actual release binary normally with its adjacent PCK.
    $smokeOutput = Invoke-EngineStage -Name 'pck-functional-smoke' -Executable $GodotPath -WorkingDirectory $packagePath -Arguments @('--main-pack', $pckPath, '--fixed-fps', '60', '--max-fps', '0', '--disable-vsync', '--audio-driver', 'Dummy', '--script', $smokeScript, '--log-file', (Join-Path $diagnosticsPath 'pck-functional-smoke.log'), '--', $screenshotPath)
    if ($smokeOutput -notmatch 'EXPORT SMOKE RESULT: \d+ checks, 0 failures') { throw 'Release smoke did not produce its success marker.' }
    $smokeOutput -split "`n" | Where-Object { $_ -match 'RESULT:|Vulkan.*Forward' } | Write-Output
    $null = Invoke-EngineStage -Name 'release-normal-start' -Executable $exePath -WorkingDirectory $packagePath -Arguments @('--fixed-fps', '60', '--audio-driver', 'Dummy', '--quit-after', '120', '--log-file', (Join-Path $diagnosticsPath 'release-normal-start.log'))
    Write-Output 'PASS: final PCK functional smoke under same-version editor runtime'
    Write-Output 'PASS: real release EXE normal startup (separate from PCK functional smoke)'
} else {
    Write-Output 'SKIP: release gameplay/startup smoke; this build remains unverified.'
}

$buildInfo = [ordered]@{
    stage = 'P7'
    target = 'Windows x86_64'
    configuration = 'release'
    engine_version = $editorVersion
    built_at_utc = [DateTime]::UtcNow.ToString('o')
    template_archive_url = 'https://github.com/godotengine/godot-builds/releases/download/4.7-stable/Godot_v4.7-stable_export_templates.tpz'
    template_archive_sha256 = $expectedArchiveHash
    template_exe_sha256 = (Get-FileHash -LiteralPath $templatePath -Algorithm SHA256).Hash.ToLowerInvariant()
    exe_sha256 = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToLowerInvariant()
    pck_sha256 = (Get-FileHash -LiteralPath $pckPath -Algorithm SHA256).Hash.ToLowerInvariant()
    pck_functional_smoke_verified = -not [bool]$SkipSmoke
    release_normal_start_verified = -not [bool]$SkipSmoke
    release_native_input_verified = $false
    human_playtest_verified = $false
}
$buildInfo | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $packagePath 'BUILD_INFO.json') -Encoding utf8
$allowedFiles = @('StarAbyss.exe', 'StarAbyss.pck', '试玩说明.txt', 'GODOT_LICENSE.txt', 'THIRD_PARTY_NOTICES.json', 'BUILD_INFO.json', 'SHA256SUMS.txt')
$unexpectedFiles = @(Get-ChildItem -LiteralPath $packagePath -Recurse -File | Where-Object { $_.DirectoryName -ne $packagePath -or $_.Name -notin $allowedFiles })
if ($unexpectedFiles.Count -gt 0) {
    throw ('Unexpected files in package directory; inspect without deleting user files: ' + ($unexpectedFiles.FullName -join ', '))
}
$hashLines = Get-ChildItem -LiteralPath $packagePath -File | Where-Object { $_.Name -ne 'SHA256SUMS.txt' } | Sort-Object Name | ForEach-Object {
    $fileHash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$fileHash  $($_.Name)"
}
Set-Content -LiteralPath (Join-Path $packagePath 'SHA256SUMS.txt') -Value $hashLines -Encoding utf8
Compress-Archive -LiteralPath $packagePath -DestinationPath $zipPath -Force
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath ($zipPath + '.sha256') -Value "$zipHash  $([IO.Path]::GetFileName($zipPath))" -Encoding utf8
Write-Output "PASS: release package $zipPath"
Write-Output "SHA256: $zipHash"
