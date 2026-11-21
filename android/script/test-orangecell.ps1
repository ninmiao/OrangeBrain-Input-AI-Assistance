$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$localJava = Get-ChildItem -Path "$projectRoot\.tools\jdk\*\bin\java.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($localJava) {
    $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $localJava.FullName)
}
Push-Location $projectRoot
try {
    & .\gradlew.bat -p shared/ai-core test --console=plain
    if ($LASTEXITCODE -ne 0) { throw "AI core tests failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}
