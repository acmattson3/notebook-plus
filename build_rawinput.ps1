$ErrorActionPreference = "Stop"

$repoRoot = "C:\Users\matts\Desktop\Git Repos\notebook-plus"
$srcDir = Join-Path $repoRoot "src"
$aarSrc = Join-Path $srcDir "rawinput\build\outputs\aar\rawinput-release.aar"
$aarDst = Join-Path $repoRoot "demo\addons\notebookplus_raw_input\bin\notebookplus_raw_input_v2.aar"

Write-Host "Building rawinput AAR..."
Push-Location $srcDir
try {
    & .\gradlew.bat :rawinput:clean :rawinput:assembleRelease --rerun-tasks
    if ($LASTEXITCODE -ne 0) {
        throw "Gradle build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

if (!(Test-Path $aarSrc)) {
    throw "AAR not found at $aarSrc"
}

Write-Host "Copying AAR to addon..."
Copy-Item -Path $aarSrc -Destination $aarDst -Force
Write-Host "Done: $aarDst"
