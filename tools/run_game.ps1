param(
    [string]$GodotPath = "",
    [switch]$ContinueFarm
)

# 直接启动独立窗口，避开编辑器嵌入预览的尺寸限制。
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($godotCommand) {
        $GodotPath = $godotCommand.Source
    } else {
        $engineDirectory = Split-Path -Parent $projectRoot
        $engineCandidates = @(Get-ChildItem -LiteralPath $engineDirectory -Filter 'Godot*_win64.exe' -File)
        if ($engineCandidates.Count -eq 1) {
            $GodotPath = $engineCandidates[0].FullName
        }
    }
}
if ([string]::IsNullOrWhiteSpace($GodotPath) -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Specify the Godot executable with -GodotPath.'
}
$gameArguments = '--path "' + $projectRoot + '"'
if ($ContinueFarm) {
    $gameArguments += ' --scene res://scenes/main.tscn'
}
# ShellExecute 在某些桌面环境中会等待 Shell 代理，直接创建进程避免启动器卡住。
$engineStart = New-Object System.Diagnostics.ProcessStartInfo
$engineStart.FileName = $GodotPath
$engineStart.Arguments = $gameArguments
$engineStart.WorkingDirectory = $projectRoot
$engineStart.UseShellExecute = $false
$engineStart.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
$engineProcess = [System.Diagnostics.Process]::Start($engineStart)
Write-Output ('Game process ID: ' + $engineProcess.Id)
