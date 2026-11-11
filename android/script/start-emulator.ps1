param([switch]$Headless)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$env:ANDROID_HOME = "$projectRoot\.tools\android-sdk"
$env:ANDROID_AVD_HOME = "$projectRoot\.tools\avd"
$emulatorArgs = @('-avd', 'RimeAI_Test', '-no-audio', '-gpu', 'swiftshader_indirect', '-memory', '2048', '-no-snapshot')
if ($Headless) { $emulatorArgs += '-no-window' }
Start-Process -FilePath "$env:ANDROID_HOME\emulator\emulator.exe" -ArgumentList $emulatorArgs -WindowStyle Hidden
