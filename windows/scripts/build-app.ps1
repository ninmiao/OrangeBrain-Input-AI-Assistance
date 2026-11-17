param([string]$BuildDir,[switch]$SkipTests)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if(!$BuildDir){$BuildDir=Join-Path $root 'windows/build/native-app'}
$cmake=(Get-Command cmake.exe -ErrorAction SilentlyContinue).Source
if(!$cmake){$cmake=(Get-ChildItem "${env:ProgramFiles(x86)}/Microsoft Visual Studio/2022/*/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName}
if(!$cmake){$cmake=(Get-ChildItem "$root/.tools/android-sdk/cmake/*/bin/cmake.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName}
if(!$cmake){throw 'Install CMake 3.18+ or Visual Studio CMake tools'}
& $cmake -S "$root/windows/app" -B $BuildDir -G 'Visual Studio 17 2022' -A x64
if($LASTEXITCODE){throw 'Native Windows configuration failed'}
& $cmake --build $BuildDir --config Release --parallel 4
if($LASTEXITCODE){throw 'Native Windows build failed'}
if(!$SkipTests){
 & "$([IO.Path]::GetDirectoryName($cmake))/ctest.exe" --test-dir $BuildDir -C Release --output-on-failure
 if($LASTEXITCODE){throw 'Native Windows tests failed'}
}
