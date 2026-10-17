param([string]$EvidenceSession = 'evidence/keeper-preview-r1')
$ErrorActionPreference = 'Stop'
$previewRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$sessionPath = [IO.Path]::GetFullPath((Join-Path $previewRoot $EvidenceSession))
if (-not $sessionPath.StartsWith($previewRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Evidence must stay inside this checkout.'
}
$review = Get-Content -LiteralPath (Join-Path $sessionPath 'delivery-review.json') -Raw | ConvertFrom-Json
$result = Get-Content -LiteralPath (Join-Path $sessionPath 'result.json') -Raw | ConvertFrom-Json
$capture = Get-Content -LiteralPath (Join-Path $sessionPath 'capture-review.json') -Raw | ConvertFrom-Json
$manifest = Get-Content -LiteralPath (Join-Path $sessionPath 'manifest.json') -Raw | ConvertFrom-Json
if ($review.delivery_passed -ne $true -or $review.actual_footage_reviewed -ne $true -or
    $result.pass -ne $true -or $result.match_full_time -ne $true -or
    $capture.capture_usable -ne $true -or $manifest.source_freeze_passed -ne $true) {
    throw 'The recorded acceptance and actual footage review must pass before promotion.'
}
$sourceBuild = Join-Path $previewRoot 'build'
$pack = Join-Path $sourceBuild 'BasedFootball.pck'
$executable = Join-Path $sourceBuild 'BasedFootball.exe'
$packHash = (Get-FileHash -LiteralPath $pack).Hash.ToLowerInvariant()
$executableHash = (Get-FileHash -LiteralPath $executable).Hash.ToLowerInvariant()
if ($packHash -ne $review.pack_sha256 -or $executableHash -ne $review.executable_sha256) {
    throw 'Build differs from the reviewed acceptance build.'
}
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop 'Based Football - Recovered 3v3.lnk'
if (-not (Test-Path -LiteralPath $shortcutPath)) { throw 'The existing recovered shortcut is missing; do not create another icon.' }
$baseline = Get-Content -LiteralPath (Join-Path $previewRoot 'evidence/fun-baseline/before.json') -Raw | ConvertFrom-Json
$oldShortcut = $baseline.files.PSObject.Properties | Where-Object { $_.Name -eq $shortcutPath }
if (-not $oldShortcut -or (Get-FileHash -LiteralPath $shortcutPath).Hash.ToLowerInvariant() -ne $oldShortcut.Value.sha256) {
    throw 'The desktop shortcut changed since the baseline; refusing to overwrite it.'
}
$releasePath = Join-Path $sourceBuild ('keeper-preview-' + $packHash.Substring(0,16))
if (Test-Path -LiteralPath $releasePath) { throw 'Refusing to overwrite a frozen release.' }
New-Item -ItemType Directory -Path $releasePath | Out-Null
Copy-Item -LiteralPath $executable -Destination (Join-Path $releasePath 'BasedFootball.exe')
Copy-Item -LiteralPath $pack -Destination (Join-Path $releasePath 'BasedFootball.pck')
$runtime = Join-Path $sourceBuild 'GodotSharp'
if (Test-Path -LiteralPath $runtime) { Copy-Item -LiteralPath $runtime -Destination $releasePath -Recurse }
if ((Get-FileHash -LiteralPath (Join-Path $releasePath 'BasedFootball.pck')).Hash.ToLowerInvariant() -ne $packHash -or
    (Get-FileHash -LiteralPath (Join-Path $releasePath 'BasedFootball.exe')).Hash.ToLowerInvariant() -ne $executableHash) {
    throw 'Frozen release verification failed; shortcut unchanged.'
}
$backup = Join-Path $releasePath 'previous-desktop-shortcut.lnk'
Copy-Item -LiteralPath $shortcutPath -Destination $backup
$shell = New-Object -ComObject WScript.Shell
$previous = $shell.CreateShortcut($shortcutPath)
$newShortcut = Join-Path $releasePath 'updated-desktop-shortcut.lnk'
$updated = $shell.CreateShortcut($newShortcut)
$updated.TargetPath = Join-Path $releasePath 'BasedFootball.exe'
$updated.WorkingDirectory = $releasePath
$updated.Arguments = ''
$updated.IconLocation = $previous.IconLocation
$updated.Description = 'Based Football - 4v4 with keepers, running touches and active receivers'
$updated.Save()
try {
    Copy-Item -LiteralPath $newShortcut -Destination $shortcutPath -Force
    $readback = $shell.CreateShortcut($shortcutPath)
    if ($readback.TargetPath -ne $updated.TargetPath -or $readback.WorkingDirectory -ne $releasePath -or $readback.Arguments -ne '') {
        throw 'Updated shortcut readback differs from the normal reviewed game.'
    }
} catch {
    Copy-Item -LiteralPath $backup -Destination $shortcutPath -Force
    throw
}
$receipt = [ordered]@{
    branch = 'codex/keeper-reception'
    installedUtc = (Get-Date).ToUniversalTime().ToString('o')
    executable = $updated.TargetPath
    packSha256 = $packHash
    executableSha256 = $executableHash
    shortcut = $shortcutPath
    previousShortcutBackup = $backup
    previousExecutable = $previous.TargetPath
    previousWorkingDirectory = $previous.WorkingDirectory
    newIconCreated = $false
    arguments = ''
    normalMainScene = 'res://scenes/match.tscn'
    customUserDirectory = 'BasedFootball-KeeperPreview'
    oldFunBuildAndSaveProfilePreserved = $true
}
$receiptText = $receipt | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText((Join-Path $releasePath 'keeper-preview-installation.json'),$receiptText)
[IO.File]::WriteAllText((Join-Path $sessionPath 'desktop-installation.json'),$receiptText)
$receiptText
