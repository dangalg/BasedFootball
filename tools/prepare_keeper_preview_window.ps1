param([Parameter(Mandatory=$true)][string]$Session, [switch]$OffScreen)
$ErrorActionPreference = 'Stop'
$previewRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$sessionRoot = [IO.Path]::GetFullPath($Session)
if (-not $sessionRoot.StartsWith($previewRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Session outside keeper preview checkout.' }
$ready = Get-Content -LiteralPath (Join-Path $sessionRoot 'ready.json') -Raw | ConvertFrom-Json
$launch = Get-Content -LiteralPath (Join-Path $sessionRoot 'launch.json') -Raw | ConvertFrom-Json
$owned = Get-Process -Id $launch.pid
if ($owned.Path -ne (Join-Path $previewRoot 'build/BasedFootball.exe')) { throw 'Process is not the owned keeper preview executable.' }
if (Test-Path -LiteralPath (Join-Path $sessionRoot 'started.json')) { throw 'Window setup is forbidden after match start.' }
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class KeeperPreviewCaptureWindow {
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h,int n);
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int hgt,uint flags);
}
'@
$handle = [IntPtr]([Int64]$ready.hwnd)
[uint32]$windowProcess = 0
[KeeperPreviewCaptureWindow]::GetWindowThreadProcessId($handle,[ref]$windowProcess) | Out-Null
if ($windowProcess -ne $owned.Id) { throw 'Native window owner mismatch.' }
[KeeperPreviewCaptureWindow]::ShowWindowAsync($handle,4) | Out-Null
# Preserve z-order and activation; only the owned preflight window is resized.
$windowX = if ($OffScreen) { 30000 } else { 24 }
$windowY = if ($OffScreen) { 30000 } else { 24 }
if (-not [KeeperPreviewCaptureWindow]::SetWindowPos($handle,[IntPtr]::Zero,$windowX,$windowY,1280,800,0x0014)) { throw 'Native preflight window resize failed.' }
Start-Sleep -Milliseconds 400
$client = New-Object KeeperPreviewCaptureWindow+Rect
if (-not [KeeperPreviewCaptureWindow]::GetClientRect($handle,[ref]$client)) { throw 'Client geometry unavailable.' }
$width = $client.Right-$client.Left
$height = $client.Bottom-$client.Top
if ($width -ne 1280 -or $height -ne 800) { throw "Unexpected native client geometry: ${width}x${height}." }
$receipt = [ordered]@{capture_token=$ready.capture_token; hwnd=$ready.hwnd; pid=$owned.Id; client_width=$width; client_height=$height; window_x=$windowX; window_y=$windowY; off_screen=[bool]$OffScreen; behavior_started=$false; set_without_activation=$true}
$path = Join-Path $sessionRoot 'window-ready.json'
if (Test-Path -LiteralPath $path) { throw 'Refusing to overwrite window readiness receipt.' }
[IO.File]::WriteAllText($path,($receipt | ConvertTo-Json))
$receipt | ConvertTo-Json
