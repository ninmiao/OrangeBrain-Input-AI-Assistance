param([string]$Device = 'emulator-5554', [switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$adb = "$projectRoot\.tools\android-sdk\platform-tools\adb.exe"
if ($Device -notmatch '^emulator-\d+$') { throw 'This fixture is only intended for a dedicated Android emulator.' }
if (!(Test-Path "$projectRoot\.tools\mock-key.pem")) {
    & python "$PSScriptRoot\setup-test-server.py"
    if ($LASTEXITCODE -ne 0) { throw 'Certificate setup failed (Python cryptography is required).' }
    $SkipBuild = $false
}
if (!$SkipBuild) { & "$PSScriptRoot\build-zephyr.ps1" -Variant debug -Abis x86_64 -IncludeTests }
$apk = Get-ChildItem "$projectRoot\android\app\build\outputs\apk\debug\*x86_64*.apk" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$test = Get-ChildItem "$projectRoot\android\app\build\outputs\apk\androidTest\debug\*.apk" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$server = Start-Process -FilePath (Get-Command python).Source -ArgumentList @('"' + "$PSScriptRoot\mock-api.py" + '"') -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput "$projectRoot\.tools\fixture-out.log" -RedirectStandardError "$projectRoot\.tools\fixture-error.log"
try {
    Start-Sleep -Seconds 1
    if ($server.HasExited) { throw 'Fixture could not start. Check .tools/fixture-error.log and port 8443.' }
    & $adb -s $Device install -r $apk.FullName
    if ($LASTEXITCODE -ne 0) { throw 'APK installation failed.' }
    & $adb -s $Device install -r $test.FullName
    if ($LASTEXITCODE -ne 0) { throw 'Test APK installation failed.' }
    & $adb -s $Device shell appops set com.osfans.trime.ai.debug MANAGE_EXTERNAL_STORAGE allow
    & $adb -s $Device shell pm grant com.osfans.trime.ai.debug android.permission.POST_NOTIFICATIONS
    $output = & $adb -s $Device shell am instrument -w -r -e class com.osfans.trime.ai.android.AiStorageTest,com.osfans.trime.ai.android.AiFlowTest,com.osfans.trime.ai.android.AiModelTest,com.osfans.trime.ai.android.AiDictionaryTest,com.osfans.trime.ai.android.AiRedesignTest,com.osfans.trime.ai.android.AiBenchmarkTest,com.osfans.trime.ai.android.SpaceCursorTest,com.osfans.trime.ai.android.PolicyAndSegmentationTest,com.osfans.trime.ai.android.CandidateCountTest,com.osfans.trime.ai.android.AiTransportRegressionTest,com.osfans.trime.ai.android.MixedInputTest com.osfans.trime.ai.debug.test/androidx.test.runner.AndroidJUnitRunner
    $output | Set-Content -Encoding UTF8 "$projectRoot\.tools\instrumentation-latest.log"
    $output | Write-Output
    if (($output -join "`n") -notmatch 'OK \(30 tests\)') { throw 'Android integration tests failed; see .tools/instrumentation-latest.log.' }
} finally {
    if (!$server.HasExited) { Stop-Process -Id $server.Id }
}
