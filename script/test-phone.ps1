param(
    [Parameter(Mandatory=$true)][string]$Device,
    [switch]$SkipBuild,
    [switch]$KeepTestApps,
    [switch]$AllowExistingTestApps
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$adb = "$projectRoot\.tools\android-sdk\platform-tools\adb.exe"
if ($Device -notmatch '^[A-Za-z0-9._:-]+$') { throw 'Invalid device identifier.' }
$state = & $adb -s $Device get-state
if ($state -ne 'device') { throw 'Device must be connected and authorized.' }
$existing = & $adb -s $Device shell pm list packages --user 0 com.osfans.trime.ai.debug
if ($existing -and !$AllowExistingTestApps) { throw 'Debug test apps already exist; use a dedicated test installation or explicitly allow reuse.' }
if (!$SkipBuild) { & "$PSScriptRoot\build-zephyr.ps1" -Variant debug -Abis arm64-v8a -IncludeTests }
$apk = Get-ChildItem "$projectRoot\app\build\outputs\apk\debug\*arm64-v8a*.apk" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$test = Get-ChildItem "$projectRoot\app\build\outputs\apk\androidTest\debug\*.apk" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (!$apk -or !$test) { throw 'ARM64 debug APK and instrumentation APK are required.' }
$originalIme = (& $adb -s $Device shell settings get secure default_input_method).Trim()
$originalAwake = (& $adb -s $Device shell settings get global stay_on_while_plugged_in).Trim()
$originalHardwareIme = (& $adb -s $Device shell settings get secure show_ime_with_hard_keyboard).Trim()
$server = $null
try {
    & $adb -s $Device install --user 0 -r $apk.FullName
    if ($LASTEXITCODE -ne 0) { throw 'Debug APK installation failed.' }
    & $adb -s $Device install --user 0 -r -t $test.FullName
    if ($LASTEXITCODE -ne 0) { throw 'Test APK installation failed.' }
    & $adb -s $Device shell appops set --user 0 com.osfans.trime.ai.debug MANAGE_EXTERNAL_STORAGE allow
    & $adb -s $Device shell pm grant --user 0 com.osfans.trime.ai.debug android.permission.POST_NOTIFICATIONS
    & $adb -s $Device shell settings put global stay_on_while_plugged_in 2
    & $adb -s $Device reverse tcp:8443 tcp:8443
    if ($LASTEXITCODE -ne 0) { throw 'adb reverse failed.' }
    $server = Start-Process -FilePath (Get-Command python).Source -ArgumentList @('"' + "$PSScriptRoot\mock-api.py" + '"') -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput "$projectRoot\.tools\phone-fixture-out.log" -RedirectStandardError "$projectRoot\.tools\phone-fixture-error.log"
    Start-Sleep -Seconds 1
    if ($server.HasExited) { throw 'Local HTTPS fixture could not start.' }
    $output = & $adb -s $Device shell am instrument --user 0 -w -r -e apiHost 127.0.0.1 -e class com.osfans.trime.ai.android.AiStorageTest,com.osfans.trime.ai.android.AiFlowTest,com.osfans.trime.ai.android.AiModelTest,com.osfans.trime.ai.android.AiDictionaryTest,com.osfans.trime.ai.android.AiRedesignTest,com.osfans.trime.ai.android.AiBenchmarkTest,com.osfans.trime.ai.android.SpaceCursorTest,com.osfans.trime.ai.android.PolicyAndSegmentationTest com.osfans.trime.ai.debug.test/androidx.test.runner.AndroidJUnitRunner
    $output | Set-Content -Encoding UTF8 "$projectRoot\.tools\instrumentation-phone.log"
    $output | Write-Output
    # adb writes successful transfer progress to stderr; Windows PowerShell must not treat it as a failure.
    $priorErrorPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $adb -s $Device pull /sdcard/Android/data/com.osfans.trime.ai.debug/files/dictionary-test-report.txt "$projectRoot\.tools\phone-dictionary-test-report.txt"
        $pullExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $priorErrorPreference }
    if ($pullExitCode -ne 0) { throw 'Could not retrieve dictionary test report.' }
    if (($output -join "`n") -notmatch 'OK \(19 tests\)') { throw 'Physical-device tests failed; see .tools/instrumentation-phone.log.' }
} finally {
    if ($server -and !$server.HasExited) { Stop-Process -Id $server.Id }
    & $adb -s $Device reverse --remove tcp:8443
    if ($originalAwake -eq 'null') { & $adb -s $Device shell settings delete global stay_on_while_plugged_in }
    else { & $adb -s $Device shell settings put global stay_on_while_plugged_in $originalAwake }
    if ($originalHardwareIme -eq 'null') { & $adb -s $Device shell settings delete secure show_ime_with_hard_keyboard }
    else { & $adb -s $Device shell settings put secure show_ime_with_hard_keyboard $originalHardwareIme }
    if ($originalIme -and $originalIme -ne 'null') { & $adb -s $Device shell ime set --user 0 $originalIme }
    & $adb -s $Device shell am force-stop --user 0 com.osfans.trime.ai.debug
    if (!$KeepTestApps -and !$existing) {
        & $adb -s $Device shell pm uninstall --user 0 com.osfans.trime.ai.debug.test
        & $adb -s $Device shell pm uninstall --user 0 com.osfans.trime.ai.debug
    }
}
