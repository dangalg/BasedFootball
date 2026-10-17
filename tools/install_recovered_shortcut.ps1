param([string]$EvidenceSession = 'evidence/recovery-match-r1')
$ErrorActionPreference = 'Stop'

$recoveryRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$recoveryPrefix = $recoveryRoot + [IO.Path]::DirectorySeparatorChar
$sessionPath = [IO.Path]::GetFullPath((Join-Path $recoveryRoot $EvidenceSession))
if (-not $sessionPath.StartsWith($recoveryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Evidence must stay inside the recovery checkout.'
}
$review = Get-Content -LiteralPath (Join-Path $sessionPath 'delivery-review.json') -Raw | ConvertFrom-Json
if ($review.recovery_delivery_passed -ne $true) { throw 'The full-match recovery review has not passed.' }

$sourceBuild = Join-Path $recoveryRoot 'build'
$sourcePack = Join-Path $sourceBuild 'BasedFootball.pck'
$sourceExecutable = Join-Path $sourceBuild 'BasedFootball.exe'
$packHash = (Get-FileHash -LiteralPath $sourcePack -Algorithm SHA256).Hash.ToLowerInvariant()
$executableHash = (Get-FileHash -LiteralPath $sourceExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
if ($packHash -ne $review.pack_sha256 -or $executableHash -ne $review.executable_sha256) {
    throw 'The build differs from the reviewed full-match build.'
}

$releasePath = Join-Path $sourceBuild ('recovered-2d5d7ad-' + $packHash.Substring(0, 16))
$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop) { throw 'Desktop folder unavailable.' }
$shortcutPath = Join-Path $desktop 'Based Football - Recovered 3v3.lnk'
if (Test-Path -LiteralPath $releasePath) { throw 'Refusing to overwrite an existing recovered release.' }
if (Test-Path -LiteralPath $shortcutPath) { throw 'Refusing to overwrite an existing desktop shortcut.' }

New-Item -ItemType Directory -Path $releasePath | Out-Null
Copy-Item -LiteralPath $sourceExecutable -Destination (Join-Path $releasePath 'BasedFootball.exe')
Copy-Item -LiteralPath $sourcePack -Destination (Join-Path $releasePath 'BasedFootball.pck')
$runtimePath = Join-Path $sourceBuild 'GodotSharp'
if (Test-Path -LiteralPath $runtimePath) {
    Copy-Item -LiteralPath $runtimePath -Destination $releasePath -Recurse
}
$iconPath = Join-Path $releasePath 'RecoveredFootball.ico'
Copy-Item -LiteralPath (Join-Path $recoveryRoot 'assets/branding/based-football.ico') -Destination $iconPath
if ((Get-FileHash -LiteralPath (Join-Path $releasePath 'BasedFootball.pck')).Hash.ToLowerInvariant() -ne $packHash -or
    (Get-FileHash -LiteralPath (Join-Path $releasePath 'BasedFootball.exe')).Hash.ToLowerInvariant() -ne $executableHash) {
    throw 'Frozen release copy verification failed; no shortcut was created.'
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $releasePath 'BasedFootball.exe'
$shortcut.WorkingDirectory = $releasePath
$shortcut.Arguments = ''
$shortcut.IconLocation = $iconPath + ',0'
$shortcut.Description = 'Recovered October 11 3v3 - separate saves - 2d5d7ad'
$shortcut.Save()
$readback = $shell.CreateShortcut($shortcutPath)
if ($readback.TargetPath -ne (Join-Path $releasePath 'BasedFootball.exe') -or $readback.Arguments -ne '') {
    throw 'Shortcut readback does not match the normal recovered game.'
}
$receipt = [ordered]@{
    sourceCommit = '2d5d7ad413f2490e1065b6224932869fccf0497f'
    branch = 'codex/recovery-3v3'
    installedUtc = (Get-Date).ToUniversalTime().ToString('o')
    executable = $readback.TargetPath
    packSha256 = $packHash
    executableSha256 = $executableHash
    shortcut = $shortcutPath
    shortcutSha256 = (Get-FileHash -LiteralPath $shortcutPath).Hash.ToLowerInvariant()
    arguments = $readback.Arguments
    normalMainScene = 'res://scenes/match.tscn'
    customUserDirectory = 'BasedFootball-Recovered-3v3'
    existingDesktopShortcutChanged = $false
}
$receiptText = $receipt | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText((Join-Path $releasePath 'recovery-installation.json'), $receiptText)
$receiptFile = Join-Path $sessionPath 'desktop-installation.json'
if (Test-Path -LiteralPath $receiptFile) { throw 'Refusing to overwrite a delivery receipt.' }
[IO.File]::WriteAllText($receiptFile, $receiptText)
$receiptText
