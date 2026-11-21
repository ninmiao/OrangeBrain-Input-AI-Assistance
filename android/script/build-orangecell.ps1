param(
    [ValidateSet('debug', 'demo')][string] $Variant = 'demo',
    [string] $Abis = 'arm64-v8a,x86_64',
    [switch] $IncludeTests
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$jdk = Get-ChildItem -Path "$projectRoot\.tools\jdk\*\bin\java.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($jdk) { $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $jdk.FullName) }
if (Test-Path "$projectRoot\.tools\android-sdk") { $env:ANDROID_HOME = "$projectRoot\.tools\android-sdk" }
$env:BUILD_ABI = $Abis
$env:DEBUG = ''
$env:PYTHON_EXECUTABLE = (Get-Command python).Source
Push-Location $projectRoot
try {
    & "$PSScriptRoot\prepare-native.ps1"
    $task = ':app:assemble' + (Get-Culture).TextInfo.ToTitleCase($Variant)
    $taskList = @($task, ':ai-core:test')
    if ($IncludeTests) { $taskList += ':app:assembleDebugAndroidTest' }
    $ErrorActionPreference = 'Continue'
    & .\gradlew.bat @taskList --console=plain
    if ($LASTEXITCODE -ne 0) { throw "Build failed ($LASTEXITCODE)" }
    & $env:PYTHON_EXECUTABLE "$PSScriptRoot/verify-apk-core.py" "$projectRoot/android/app/build/outputs/apk/$Variant"
    if ($LASTEXITCODE -ne 0) { throw "APK core packaging verification failed" }
} finally { Pop-Location }
