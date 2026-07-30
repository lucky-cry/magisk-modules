# build.ps1 - Magisk 模块打包脚本（仅储存模式）
$MODDIR = $PSScriptRoot
if (-not $MODDIR) { $MODDIR = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $MODDIR) { $MODDIR = Get-Location }

$versionLine = Get-Content "$MODDIR\module.prop" | Where-Object { $_ -match "^version=" }
$VERSION = ($versionLine -split "=", 2)[1].Trim()
$OUTPUT = "$MODDIR\freeze_logd_switch_$VERSION.zip"

Write-Host "打包模块: freeze_logd_switch $VERSION"

if (Test-Path $OUTPUT) { Remove-Item $OUTPUT -Force }

$files = @("action.sh","cron_check.sh","customize.sh","lib_core.sh","module.prop","scene_restart.sh","service.sh","uninstall.sh","cron.d","META-INF")

Add-Type -Assembly System.IO.Compression
Add-Type -Assembly System.IO.Compression.FileSystem

$zip = [System.IO.Compression.ZipFile]::Open($OUTPUT, [System.IO.Compression.ZipArchiveMode]::Create)

foreach ($file in $files) {
    $path = Join-Path $MODDIR $file
    if (Test-Path $path -PathType Container) {
        Get-ChildItem $path -Recurse -File | ForEach-Object {
            $entryName = $_.FullName.Substring($MODDIR.Length + 1).Replace("\", "/")
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $entryName, [System.IO.Compression.CompressionLevel]::NoCompression) | Out-Null
            Write-Host "  + $entryName"
        }
    } elseif (Test-Path $path) {
        $entryName = $file
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $path, $entryName, [System.IO.Compression.CompressionLevel]::NoCompression) | Out-Null
        Write-Host "  + $entryName"
    }
}

$zip.Dispose()

if (Test-Path $OUTPUT) {
    $size = (Get-Item $OUTPUT).Length / 1KB
    Write-Host ""
    Write-Host "打包成功: freeze_logd_switch_$VERSION.zip ($([math]::Round($size, 1)) KB)"
} else {
    Write-Host "打包失败"
}
