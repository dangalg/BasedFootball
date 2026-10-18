param(
    [Parameter(Mandatory=$true)][string]$EvidenceSession,
    [switch]$ForHumanEvaluation
)
$ErrorActionPreference = 'Stop'
$previewRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$sessionPath = [IO.Path]::GetFullPath((Join-Path $previewRoot $EvidenceSession))
if (-not $sessionPath.StartsWith($previewRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Session outside this checkout.' }
$review = Get-Content -LiteralPath (Join-Path $sessionPath 'delivery-review.json') -Raw | ConvertFrom-Json
$result = Get-Content -LiteralPath (Join-Path $sessionPath 'result.json') -Raw | ConvertFrom-Json
$capture = Get-Content -LiteralPath (Join-Path $sessionPath 'capture-review.json') -Raw | ConvertFrom-Json
$manifest = Get-Content -LiteralPath (Join-Path $sessionPath 'manifest.json') -Raw | ConvertFrom-Json
$approvedEvaluation = $ForHumanEvaluation -and $review.user_requested_playable_preview -eq $true -and $review.user_acknowledged_failed_checks -eq $true
if ($manifest.source_freeze_passed -ne $true -or $review.actual_footage_reviewed -ne $true) { throw 'Recorded build identity or actual footage review is unverified.' }
if ($capture.capture_usable -ne $true -and -not $approvedEvaluation) { throw 'A failed capture gate requires explicit approval to deliver this candidate for human evaluation.' }
if ($review.ready_for_human_evaluation -ne $true) { throw 'The reviewed build is not marked ready for human evaluation.' }
if ($result.pass -ne $true -and -not $approvedEvaluation) { throw 'Unresolved diagnostic checks require explicit approval to deliver this candidate for human evaluation.' }
$baseline = Get-Content -LiteralPath (Join-Path $previewRoot 'evidence/turn-teamwork-baseline/before.json') -Raw | ConvertFrom-Json
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Based Football - Recovered 3v3.lnk'
if (-not (Test-Path -LiteralPath $shortcutPath) -or (Get-FileHash -LiteralPath $shortcutPath).Hash.ToLowerInvariant() -ne $baseline.shortcut_sha256) { throw 'Existing desktop shortcut changed since the baseline.' }
foreach ($property in $baseline.frozen_files.PSObject.Properties) {
    if (-not (Test-Path -LiteralPath $property.Name) -or (Get-FileHash -LiteralPath $property.Name).Hash.ToLowerInvariant() -ne $property.Value) { throw 'A preserved playable file changed.' }
}
$sourceBuild = Join-Path $previewRoot 'build'
$pack = Join-Path $sourceBuild 'BasedFootball.pck'
$executable = Join-Path $sourceBuild 'BasedFootball.exe'
$packHash = (Get-FileHash -LiteralPath $pack).Hash.ToLowerInvariant()
$executableHash = (Get-FileHash -LiteralPath $executable).Hash.ToLowerInvariant()
if ($packHash -ne $review.pack_sha256 -or $executableHash -ne $review.executable_sha256 -or
    $packHash -ne $manifest.artifact_hashes.'build/BasedFootball.pck' -or $executableHash -ne $manifest.artifact_hashes.'build/BasedFootball.exe') { throw 'Build differs from the recorded review.' }
$releasePath = Join-Path $sourceBuild ('turn-teamwork-' + $packHash.Substring(0,16))
if (Test-Path -LiteralPath $releasePath) { throw 'Refusing to overwrite a frozen release.' }
New-Item -ItemType Directory -Path $releasePath | Out-Null
Copy-Item -LiteralPath $executable -Destination (Join-Path $releasePath 'BasedFootball.exe')
Copy-Item -LiteralPath $pack -Destination (Join-Path $releasePath 'BasedFootball.pck')
$runtime = Join-Path $sourceBuild 'GodotSharp'
if (Test-Path -LiteralPath $runtime) { Copy-Item -LiteralPath $runtime -Destination $releasePath -Recurse }
if ((Get-FileHash -LiteralPath (Join-Path $releasePath 'BasedFootball.pck')).Hash.ToLowerInvariant() -ne $packHash -or
    (Get-FileHash -LiteralPath (Join-Path $releasePath 'BasedFootball.exe')).Hash.ToLowerInvariant() -ne $executableHash) { throw 'Frozen copy verification failed; desktop unchanged.' }
$backup = Join-Path $releasePath 'previous-desktop-shortcut.lnk'
Copy-Item -LiteralPath $shortcutPath -Destination $backup
$shell = New-Object -ComObject WScript.Shell
$previous = $shell.CreateShortcut($shortcutPath)
$previousTarget = $previous.TargetPath
$newPath = Join-Path $releasePath 'updated-desktop-shortcut.lnk'
$updated = $shell.CreateShortcut($newPath)
$updated.TargetPath = Join-Path $releasePath 'BasedFootball.exe'
$updated.WorkingDirectory = $releasePath
$updated.Arguments = ''
$updated.IconLocation = $previous.IconLocation
$updated.Description = 'Based Football 4v4 - gentle turn touches and team passing'
$updated.Save()
try {
    Copy-Item -LiteralPath $newPath -Destination $shortcutPath -Force
    $readback = $shell.CreateShortcut($shortcutPath)
    if ($readback.TargetPath -ne $updated.TargetPath -or $readback.WorkingDirectory -ne $releasePath -or $readback.Arguments -ne '') { throw 'Shortcut readback mismatch.' }
} catch {
    Copy-Item -LiteralPath $backup -Destination $shortcutPath -Force
    throw
}
$receipt = [ordered]@{
    installedUtc = (Get-Date).ToUniversalTime().ToString('o')
    branch = 'codex/keeper-reception'
    executable = $updated.TargetPath
    packSha256 = $packHash
    executableSha256 = $executableHash
    shortcut = $shortcutPath
    previousExecutable = $previousTarget
    previousShortcutBackup = $backup
    newIconCreated = $false
    arguments = ''
    customUserDirectory = 'BasedFootball-KeeperPreview'
    automatedChecksPassed = $result.pass
    originalCaptureGatePassed = $capture.capture_usable
    humanEvaluationPreview = [bool]$ForHumanEvaluation
    userApprovedEvaluationDespiteFailedChecks = [bool]$approvedEvaluation
    gameplayChangedAfterRecordedRun = $false
}
$receiptText = $receipt | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText((Join-Path $releasePath 'preview-installation.json'),$receiptText)
[IO.File]::WriteAllText((Join-Path $sessionPath 'desktop-installation.json'),$receiptText)
$receiptText
