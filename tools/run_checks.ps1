param(
	[string]$GodotPath = '',
	[string[]]$Suites = @(),
	[ValidateRange(1, 3600)][int]$TimeoutSeconds = 180,
	[switch]$Windowed,
	[switch]$Preview,
	[switch]$Packaged,
	[switch]$EnableDevTools
)
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 lacks [IO.Path]::GetRelativePath (that is .NET Core only),
# so trim the root prefix instead. Works on both 5.1 and pwsh.
function Get-RelativePath([string]$root, [string]$full) {
	$prefix = $root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
	if ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
		return $full.Substring($prefix.Length).Replace('\', '/')
	}
	return $full
}

$Suites = @($Suites | ForEach-Object { $_ -split ',' })
$runPackaged = $Packaged -or $Suites.Count -eq 0
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
function Get-SourceFingerprint([string]$root) {
	$records = foreach ($folder in @('scripts', 'scenes', 'data', 'tools', 'assets', 'addons')) {
		Get-ChildItem -LiteralPath (Join-Path $root $folder) -Recurse -File |
			Where-Object { $_.Extension -in @('.gd', '.tscn', '.tres', '.ps1', '.py', '.gdshader', '.cfg', '.png', '.svg', '.wav', '.ogg', '.ttf', '.otf', '.json', '.uid', '.import') } |
			ForEach-Object { (Get-RelativePath $root $_.FullName) + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
	}
	foreach ($file in @('project.godot', 'export_presets.cfg', 'CREDITS.md')) {
		$records += $file + ':' + (Get-FileHash -LiteralPath (Join-Path $root $file) -Algorithm SHA256).Hash
	}
	return ($records | Sort-Object) -join "`n"
}
function Copy-CheckTree([string]$source, [string]$destination) {
	& robocopy $source $destination /E /COPY:DAT /R:1 /W:1 /MT:16 /XJ /NFL /NDL /NJH /NJS /NP | Out-Null
	if ($LASTEXITCODE -ge 8) { throw "Snapshot copy failed: $source" }
}
if (-not $GodotPath) {
	$installed = Get-Command godot -ErrorAction SilentlyContinue
	if ($installed) { $GodotPath = $installed.Source }
	else { $GodotPath = Join-Path (Split-Path $projectRoot) 'Godot_v4.7.2-stable_win64_console.exe' }
}
if (-not (Test-Path -LiteralPath $GodotPath)) { throw "Godot executable not found: $GodotPath" }
$runId = [Guid]::NewGuid().ToString('N')
$auditRoot = Join-Path ([IO.Path]::GetTempPath()) ('PixelFarmChecks_' + $runId)
New-Item -ItemType Directory -Path $auditRoot | Out-Null
Write-Output "Snapshotting sources and assets: $auditRoot"
$sourceBefore = Get-SourceFingerprint $projectRoot
foreach ($folder in @('scripts', 'scenes', 'data', 'assets', 'art', 'addons', 'tools')) {
	Copy-CheckTree (Join-Path $projectRoot $folder) (Join-Path $auditRoot $folder)
}
foreach ($file in @('icon.svg', 'export_presets.cfg', 'CREDITS.md', 'README.md', 'project.godot')) {
	if (Test-Path -LiteralPath (Join-Path $projectRoot $file)) {
		Copy-Item -LiteralPath (Join-Path $projectRoot $file) -Destination (Join-Path $auditRoot $file)
	}
}
New-Item -ItemType Directory -Path (Join-Path $auditRoot '.godot') | Out-Null
Copy-CheckTree (Join-Path $projectRoot '.godot/imported') (Join-Path $auditRoot '.godot/imported')
foreach ($cache in @('global_script_class_cache.cfg', 'uid_cache.bin')) {
	Copy-Item -LiteralPath (Join-Path $projectRoot ('.godot/' + $cache)) -Destination (Join-Path $auditRoot ('.godot/' + $cache))
}
$sourceAfter = Get-SourceFingerprint $projectRoot
if ($sourceBefore -ne $sourceAfter) {
	# 并行工作区只同步已变化的文件，再验证完整指纹；不放宽固定快照要求。
	Write-Output 'Source changed while copying; synchronizing changed files before freezing snapshot.'
	$matched = $false
	for ($attempt = 0; $attempt -lt 3; $attempt++) {
		$snapshotFingerprint = Get-SourceFingerprint $auditRoot
		$sourceAfter = Get-SourceFingerprint $projectRoot
		if ($snapshotFingerprint -eq $sourceAfter) { $matched = $true; break }
		$sourceRecords = @{}
		foreach ($line in ($sourceAfter -split "`n")) {
			$separator = $line.LastIndexOf(':')
			$sourceRecords[$line.Substring(0, $separator)] = $line.Substring($separator + 1)
		}
		$snapshotRecords = @{}
		foreach ($line in ($snapshotFingerprint -split "`n")) {
			$separator = $line.LastIndexOf(':')
			$name = $line.Substring(0, $separator)
			if (-not $sourceRecords.ContainsKey($name)) { throw 'Files were removed during snapshot creation; rerun to create a fresh snapshot.' }
			$snapshotRecords[$name] = $line.Substring($separator + 1)
		}
		foreach ($name in $sourceRecords.Keys) {
			if ($snapshotRecords[$name] -eq $sourceRecords[$name]) { continue }
			$destination = Join-Path $auditRoot $name
			New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
			Copy-Item -LiteralPath (Join-Path $projectRoot $name) -Destination $destination
		}
	}
	# 最后一轮同步后仍完整核对，持续写入不能让混合快照进入验证。
	if (-not $matched) {
		$snapshotFingerprint = Get-SourceFingerprint $auditRoot
		$sourceAfter = Get-SourceFingerprint $projectRoot
		$matched = $snapshotFingerprint -eq $sourceAfter
	}
	if (-not $matched) { throw 'Source files kept changing during snapshot creation; rerun after the current edits finish.' }
}
[IO.File]::WriteAllText((Join-Path $auditRoot 'source_manifest.txt'), $sourceAfter)
$config = [IO.File]::ReadAllText((Join-Path $projectRoot 'project.godot'))
$config = $config -replace '(?m)^enabled=PackedStringArray\(.*\)$', 'enabled=PackedStringArray()'
$checks = @(Get-ChildItem -LiteralPath (Join-Path $auditRoot 'tools/check') -Filter '*.gd' |
	Where-Object { $_.Name -eq 'smoke_check.gd' -or $_.Name.StartsWith('check_') } | Sort-Object Name)
if ($Suites.Count) {
	$checks = @($checks | Where-Object { $_.BaseName -in $Suites -or $_.Name -in $Suites })
	if ($checks.Count -ne $Suites.Count) { throw 'Unknown or duplicate suite name' }
}
if (-not $checks.Count) { throw 'No check suites found' }
$report = [Collections.Generic.List[object]]::new()
Write-Output "Isolated project and logs: $auditRoot"
$importConfig = $config.Replace('[application]', "[application]`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=`"PixelFarmChecks_${runId}_import`"")
[IO.File]::WriteAllText((Join-Path $auditRoot 'project.godot'), $importConfig)
$importInfo = [Diagnostics.ProcessStartInfo]::new()
$importInfo.FileName = [IO.Path]::GetFullPath($GodotPath)
$importInfo.Arguments = '--headless --editor --import --path "' + $auditRoot + '"'
$importInfo.UseShellExecute = $false
$importInfo.CreateNoWindow = $true
$importInfo.RedirectStandardOutput = $true
$importInfo.RedirectStandardError = $true
$importProcess = [Diagnostics.Process]::Start($importInfo)
$importOut = $importProcess.StandardOutput.ReadToEndAsync()
$importErr = $importProcess.StandardError.ReadToEndAsync()
$importFinished = $importProcess.WaitForExit($TimeoutSeconds * 1000)
if (-not $importFinished) { $importProcess.Kill($true) }
$importLog = $importOut.GetAwaiter().GetResult() + "`n" + $importErr.GetAwaiter().GetResult()
[IO.File]::WriteAllText((Join-Path $auditRoot 'import.log'), $importLog)
if (-not $importFinished -or $importProcess.ExitCode -ne 0 -or $importLog -match '(?m)SCRIPT ERROR:|^ERROR:') {
	throw "Resource preflight failed. See $auditRoot/import.log"
}
$importProcess.Dispose()
Write-Output 'Resource preflight: PASS'
foreach ($check in $checks) {
	$userDir = 'PixelFarmChecks_' + $runId + '_' + $check.BaseName
	$testConfig = $config.Replace('[application]', "[application]`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=`"$userDir`"")
	[IO.File]::WriteAllText((Join-Path $auditRoot 'project.godot'), $testConfig)
	$info = [Diagnostics.ProcessStartInfo]::new()
	$info.FileName = [IO.Path]::GetFullPath($GodotPath)
	$runtimeMode = if ($Windowed) { '--rendering-method gl_compatibility' } else { '--headless' }
	$info.Arguments = $runtimeMode + ' --path "' + $auditRoot + '" --script res://tools/check/' + $check.Name
	if ($Preview) { $info.Arguments += ' -- --preview' }
	if ($EnableDevTools) { $info.Arguments += $(if ($Preview) { ' --enable-dev-tools' } else { ' -- --enable-dev-tools' }) }
	$info.UseShellExecute = $false
	$info.CreateNoWindow = $true
	$info.RedirectStandardOutput = $true
	$info.RedirectStandardError = $true
	$process = [Diagnostics.Process]::Start($info)
	$stdout = $process.StandardOutput.ReadToEndAsync()
	$stderr = $process.StandardError.ReadToEndAsync()
	$finished = $process.WaitForExit($TimeoutSeconds * 1000)
	if (-not $finished) { $process.Kill($true) }
	$log = $stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()
	[IO.File]::WriteAllText((Join-Path $auditRoot ($check.BaseName + '.log')), $log)
	$scriptErrors = $log -match 'SCRIPT ERROR:|Parse Error:|Assertion failed|\] FAIL[: ]'
	$engineErrors = @($log -split "`n" | Where-Object { $_ -match '^ERROR:' })
	$summary = $log -match '(?im)\[[^\]]+\].*(PASS|0 failures|0 errors|all checks passed)'
	$warnings = $log -match 'ObjectDB instances were leaked|resources still in use at exit'
	$lifecycle = $log -match '\[checks\] lifecycle complete; exit=0'
	$passed = $finished -and $process.ExitCode -eq 0 -and -not $scriptErrors -and $engineErrors.Count -eq 0 -and -not $warnings -and $summary -and $lifecycle
	$result = [pscustomobject]@{ Suite = $check.BaseName; Passed = $passed; ExitCode = $process.ExitCode; ExitResourceWarning = $warnings }
	$report.Add($result)
	Write-Output (('{0}: {1}' -f $check.BaseName, $(if ($passed) { 'PASS' } else { 'FAIL' })))
	if (-not $passed) {
		$log -split "`n" | Where-Object { $_ -match 'SCRIPT ERROR:|^ERROR:|\] FAIL|Parse Error:' } | Select-Object -First 24 | Write-Output
	}
	$process.Dispose()
}
if ($runPackaged) {
	$packPath = Join-Path $auditRoot 'verification.pck'
	# 空目录阻止缺失的包内资源回退到工作区，真正验证仅靠 PCK 能运行。
	$packRuntimeRoot = Join-Path $auditRoot 'pack-runtime'
	New-Item -ItemType Directory -Path $packRuntimeRoot | Out-Null
	$packPassed = $true
	$packExit = -1
	$packWarnings = $false
	foreach ($phase in @('export', 'runtime')) {
		$packInfo = [Diagnostics.ProcessStartInfo]::new()
		$packInfo.FileName = [IO.Path]::GetFullPath($GodotPath)
		if ($phase -eq 'export') {
			$packInfo.Arguments = '--headless --editor --path "' + $auditRoot + '" --export-pack "Windows Desktop" "' + $packPath + '"'
		} else {
			$mode = if ($Windowed) { '--rendering-method gl_compatibility' } else { '--headless' }
			$packInfo.WorkingDirectory = $packRuntimeRoot
			$packInfo.Arguments = $mode + ' --path "' + $packRuntimeRoot + '" --main-pack "' + $packPath + '" --script "' + (Join-Path $auditRoot 'tools/lib/packaged_smoke.gd') + '" -- --enable-dev-tools'
		}
		$packInfo.UseShellExecute = $false
		$packInfo.CreateNoWindow = $true
		$packInfo.RedirectStandardOutput = $true
		$packInfo.RedirectStandardError = $true
		$packProcess = [Diagnostics.Process]::Start($packInfo)
		$packOut = $packProcess.StandardOutput.ReadToEndAsync()
		$packErr = $packProcess.StandardError.ReadToEndAsync()
		$packFinished = $packProcess.WaitForExit($TimeoutSeconds * 1000)
		if (-not $packFinished) { $packProcess.Kill($true) }
		$packLog = $packOut.GetAwaiter().GetResult() + "`n" + $packErr.GetAwaiter().GetResult()
		[IO.File]::WriteAllText((Join-Path $auditRoot ('packaged_' + $phase + '.log')), $packLog)
		$packExit = $packProcess.ExitCode
		$packWarnings = $packLog -match 'ObjectDB instances were leaked|resources still in use at exit'
		$packPassed = $packFinished -and $packExit -eq 0 -and -not $packWarnings -and $packLog -notmatch '(?m)SCRIPT ERROR:|^ERROR:|Parse Error:|Assertion failed|\] FAIL[: ]'
		if ($phase -eq 'runtime') {
			$packPassed = $packPassed -and $packLog -match '\[packaged_runtime\].*PASS' -and $packLog -match '\[checks\] lifecycle complete; exit=0'
		}
		$packProcess.Dispose()
		Write-Output ('Packaged {0}: {1}' -f $phase, $(if ($packPassed) { 'PASS' } else { 'FAIL' }))
		if (-not $packPassed) {
			$packLog -split "`n" | Where-Object { $_ -match 'SCRIPT ERROR:|^ERROR:|\] FAIL|Parse Error:' } | Select-Object -First 24 | Write-Output
			break
		}
	}
	$report.Add([pscustomobject]@{ Suite = 'check_packaged_runtime'; Passed = $packPassed; ExitCode = $packExit; ExitResourceWarning = $packWarnings })
}
$report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $auditRoot 'results.json') -Encoding utf8
$failures = @($report | Where-Object { -not $_.Passed }).Count
Write-Output ("Completed: {0} suites, {1} failures; logs: {2}" -f $report.Count, $failures, $auditRoot)
if ($failures) { exit 1 }

exit 0
