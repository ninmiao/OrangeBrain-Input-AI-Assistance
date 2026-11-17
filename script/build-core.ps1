param([string]$BuildDir)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(!$BuildDir){$BuildDir="$root/shared/native-core/build"}
if(!$env:JAVA_HOME){$env:JAVA_HOME=(Get-ChildItem "$root/.tools/jdk/*/bin/java.exe" | Select-Object -First 1).Directory.Parent.FullName}
$cmake=(Get-Command cmake.exe -ErrorAction SilentlyContinue).Source
if(!$cmake){$cmake=(Get-ChildItem "$root/.tools/android-sdk/cmake/*/bin/cmake.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName}
if(!$cmake){$cmake=(Get-ChildItem "${env:ProgramFiles(x86)}/Microsoft Visual Studio/2022/*/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName}
if(!$cmake){throw 'Install CMake 3.18+ or the VS CMake tools, and add cmake.exe to PATH'}
& $cmake -S "$root/shared/native-core" -B $BuildDir -G 'Visual Studio 17 2022' -A x64
if($LASTEXITCODE){throw 'Native core configuration failed'}
& $cmake --build $BuildDir --config Release --parallel 4
if($LASTEXITCODE){throw 'Native core build failed'}
& "$([IO.Path]::GetDirectoryName($cmake))/ctest.exe" --test-dir $BuildDir -C Release --output-on-failure
if($LASTEXITCODE){throw 'Native core tests failed'}
