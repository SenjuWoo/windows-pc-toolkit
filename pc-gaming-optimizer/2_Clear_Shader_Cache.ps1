<#
.SYNOPSIS
    Clears GPU shader caches (NVIDIA DXCache, GLCache, D3DSCache, DXNVCache, etc.)
    to resolve stuttering and ensure fresh shader compilation.

.DESCRIPTION
    Safely removes cached shader files from common locations using $env:LOCALAPPDATA
    so it works for any user on any PC.

.NOTES
    Run normally (no admin required). Some files may be in use and will be skipped.
#>

Write-Host "=== GPU Shader Cache Cleaner ===" -ForegroundColor Cyan
Write-Host "This will clear shader caches for NVIDIA, AMD, Intel, DirectX, and Windows." -ForegroundColor Gray
Write-Host ""

$caches = @(
    @{ Name = "NVIDIA DXCache";          Path = "$env:LOCALAPPDATA\NVIDIA\DXCache" },
    @{ Name = "NVIDIA GLCache";          Path = "$env:LOCALAPPDATA\NVIDIA\GLCache" },
    @{ Name = "NVIDIA DXNVCache";        Path = "$env:LOCALAPPDATA\NVIDIA\DXNVCache" },
    @{ Name = "NVIDIA ComputeCache";     Path = "$env:LOCALAPPDATA\NVIDIA\ComputeCache" },
    @{ Name = "NVIDIA OptixCache";       Path = "$env:LOCALAPPDATA\NVIDIA\OptixCache" },
    @{ Name = "NVIDIA NV_Cache";         Path = "$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache" },
    @{ Name = "AMD DxCache";             Path = "$env:LOCALAPPDATA\AMD\DxCache" },
    @{ Name = "AMD DxcCache";            Path = "$env:LOCALAPPDATA\AMD\DxcCache" },
    @{ Name = "AMD GLCache";             Path = "$env:LOCALAPPDATA\AMD\GLCache" },
    @{ Name = "AMD VkCache";             Path = "$env:LOCALAPPDATA\AMD\VkCache" },
    @{ Name = "Intel ShaderCache";       Path = "$env:LOCALAPPDATA\Intel\ShaderCache" },
    @{ Name = "D3D Shader Cache";        Path = "$env:LOCALAPPDATA\D3DSCache" },
    @{ Name = "Windows DXCache (DirectX)";              Path = "$env:LOCALAPPDATA\Microsoft\Windows\DXCache" }
)

$totalFiles = 0
$totalSizeMB = 0

Write-Host "=== Scanning cache directories ===" -ForegroundColor Cyan

foreach ($cache in $caches) {
    $name = $cache.Name
    $path = $cache.Path
    
    if (Test-Path $path) {
        $items = Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue
        $count = $items.Count
        $size = ($items | Measure-Object -Property Length -Sum).Sum
        $sizeMB = [math]::Round($size / 1MB, 2)
        $totalFiles += $count
        $totalSizeMB += $sizeMB
        
        if ($count -gt 0) {
            Write-Host "  [$name]  $count files, $sizeMB MB" -ForegroundColor Yellow
        } else {
            Write-Host "  [$name]  Empty" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  [$name]  Not found" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "Total: $totalFiles files, $([math]::Round($totalSizeMB, 2)) MB" -ForegroundColor Cyan

if ($totalFiles -eq 0) {
    Write-Host "Nothing to clean!" -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "=== Clearing caches... ===" -ForegroundColor Cyan

$clearedFiles = 0
$clearedSizeMB = 0

foreach ($cache in $caches) {
    $path = $cache.Path
    if (Test-Path $path) {
        $items = Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            try {
                $size = $item.Length
                Remove-Item -Path $item.FullName -Force -ErrorAction Stop
                $clearedFiles++
                $clearedSizeMB += $size / 1MB
            }
            catch {
                # File in use or permission denied - skip silently
            }
        }
        Write-Host "  Cleared: $($cache.Name)" -ForegroundColor Green
    }
}

$clearedSizeMB = [math]::Round($clearedSizeMB, 2)
Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host "Cleared: $clearedFiles files, $clearedSizeMB MB" -ForegroundColor Green
Write-Host ""
Write-Host "Note: Some files may have been in use and were skipped." -ForegroundColor Gray
Write-Host "Run again after a reboot to catch any remaining files." -ForegroundColor Gray