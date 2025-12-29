$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$exportDirs = Get-ChildItem -Directory | Where-Object { $_.Name -match '^(?<platform>.+?)[-_]export$' }

if (-not $exportDirs) {
    Write-Host "No <platform>_export or <platform>-export directories found in $scriptDir" -ForegroundColor Yellow
    exit 0
}

foreach ($dir in $exportDirs) {
    if ($dir.Name -notmatch '^(?<platform>.+?)[-_]export$') {
        continue
    }
    $platform = $Matches['platform']
    $zipName = "NotebookPlus_${platform}.zip"
    $zipPath = Join-Path $scriptDir $zipName

    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }

    Write-Host "Zipping $($dir.Name) -> $zipName"
    Compress-Archive -Path (Join-Path $dir.FullName '*') -DestinationPath $zipPath
}

Write-Host "Done." -ForegroundColor Green
