param([switch]$Build, [switch]$Acceptance, [switch]$DribbleAcceptance, [switch]$Editor, [string]$OutputDirectory = 'build')
$ErrorActionPreference = 'Stop'
$taskEnginePath = 'C:\Program Files\Godot\Godot_v4.6.1-stable_mono_win64\Godot_v4.6.1-stable_mono_win64_console.exe'
if ($env:GODOT_EXE) { $taskEnginePath = $env:GODOT_EXE }
if (-not (Test-Path -LiteralPath $taskEnginePath)) { throw 'Godot 4.6.1 is required. Set GODOT_EXE to its console executable.' }
$taskEvidencePath = Join-Path $PSScriptRoot 'evidence'
New-Item -ItemType Directory -Path $taskEvidencePath -Force | Out-Null
Set-Content -LiteralPath (Join-Path $taskEvidencePath '.gdignore') -Value ''
if ($Build) {
    $taskBuildPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $OutputDirectory))
    if (-not $taskBuildPath.StartsWith(([IO.Path]::GetFullPath($PSScriptRoot) + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) { throw 'Build output must stay inside the project.' }
    New-Item -ItemType Directory -Path $taskBuildPath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $taskBuildPath '.gdignore') -Value ''
    $taskBuildLog = Join-Path $taskEvidencePath 'build.log'
    & $taskEnginePath --headless --editor --path $PSScriptRoot --import --quit --log-file $taskBuildLog
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $taskBuildLog -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet)) { throw 'Godot project import failed. See evidence/build.log.' }
    $taskExportLog = Join-Path $taskEvidencePath 'export.log'
    & $taskEnginePath --headless --path $PSScriptRoot --export-pack 'Windows Desktop' (Join-Path $taskBuildPath 'BasedFootball.pck') --log-file $taskExportLog
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $taskExportLog -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet)) { throw 'Game pack export failed. See evidence/export.log.' }
    # Local playable bundle: reuse the pinned installed engine, avoiding a template download.
    $taskGraphicalEngine = $taskEnginePath -replace '_console\.exe$', '.exe'
    if (-not (Test-Path -LiteralPath $taskGraphicalEngine)) { throw 'Graphical Godot executable missing.' }
    Copy-Item -LiteralPath $taskGraphicalEngine -Destination (Join-Path $taskBuildPath 'BasedFootball.exe') -Force
    $taskRuntime = Join-Path (Split-Path -Parent $taskGraphicalEngine) 'GodotSharp'
    if (Test-Path -LiteralPath $taskRuntime) {
        Copy-Item -LiteralPath $taskRuntime -Destination $taskBuildPath -Recurse -Force
    }
    Write-Output "BUILD_OK: $taskBuildPath\BasedFootball.exe"
    exit 0
}
if ($Editor) { & $taskEnginePath --editor --path $PSScriptRoot; exit $LASTEXITCODE }
if ($Acceptance -or $DribbleAcceptance) {
    $taskPlayable = Join-Path $PSScriptRoot 'build\BasedFootball.exe'
    if (-not (Test-Path -LiteralPath $taskPlayable)) { throw 'Build before acceptance.' }
    $env:BASED_FOOTBALL_EVIDENCE = $taskEvidencePath
    $taskTestArgument = if ($DribbleAcceptance) { '--dribble-acceptance' } else { '--acceptance' }
    $taskLogName = if ($DribbleAcceptance) { 'dribble-acceptance.log' } else { 'acceptance.log' }
    $taskAcceptanceLog = Join-Path $taskEvidencePath $taskLogName
    # Render off-screen and request a hidden window so tests do not cover another game.
    $taskGame = Start-Process -FilePath $taskPlayable -ArgumentList @('--position', '30000,30000', '--log-file', ('"' + $taskAcceptanceLog + '"'), '--', $taskTestArgument) -WorkingDirectory (Split-Path -Parent $taskPlayable) -WindowStyle Hidden -PassThru
    # One native completion wait; no process/status polling.
    $taskGame.WaitForExit()
    exit $taskGame.ExitCode
}
$taskPlayable = Join-Path $PSScriptRoot 'build\BasedFootball.exe'
if (Test-Path -LiteralPath $taskPlayable) {
    Start-Process -FilePath $taskPlayable -WorkingDirectory (Split-Path -Parent $taskPlayable) -WindowStyle Normal
} else {
    $taskGraphicalEngine = $taskEnginePath -replace '_console\.exe$', '.exe'
    Start-Process -FilePath $taskGraphicalEngine -ArgumentList @('--path', $PSScriptRoot) -WindowStyle Normal
}
