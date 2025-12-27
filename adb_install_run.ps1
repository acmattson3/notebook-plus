$ErrorActionPreference = "Stop"

# Update these if your package/activity changes.
$packageName = "com.example.notebookplus"
$activityName = "com.godot.game.GodotApp"
$apkPath = "C:\Users\matts\Desktop\Git Repos\notebook-plus\android-export\NotebookPlus.apk"

if (!(Test-Path $apkPath)) {
    Write-Host "APK not found at $apkPath" -ForegroundColor Red
    Write-Host "Edit $($MyInvocation.MyCommand.Path) and set $apkPath to your exported APK." -ForegroundColor Yellow
    exit 1
}

Write-Host "Installing APK..."
& adb install -r $apkPath
if ($LASTEXITCODE -ne 0) { throw "adb install failed" }

Write-Host "Launching app..."
& adb shell am start -n "$packageName/$activityName"
if ($LASTEXITCODE -ne 0) { throw "adb start failed" }

Write-Host "Done." -ForegroundColor Green
