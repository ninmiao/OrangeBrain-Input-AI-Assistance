param([ValidateSet('x64','Win32','both')][string]$Architecture='both')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$vswhere="${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(!$vs){throw 'Visual Studio 2022 C++ Build Tools required; see docs/DEVELOPMENT.md'}
$boost=Join-Path $root 'android/app/src/main/jni/boost'
if(!(Test-Path "$boost/boost")){throw 'Prepare Boost headers/libraries first: windows/scripts/prepare-deps.py'}
$native=Join-Path $root 'windows/native'
$properties=[IO.File]::ReadAllText("$native/weasel.props.template")
# One product version for every signed binary: windows/app/CMakeLists.txt.
$cmake=[IO.File]::ReadAllText("$root/windows/app/CMakeLists.txt")
if($cmake -notmatch 'project\(ZephyrWindows VERSION (\d+)\.(\d+)\.(\d+)'){throw 'Cannot read the Windows version from windows/app/CMakeLists.txt'}
$version="$($Matches[1]).$($Matches[2]).$($Matches[3])"
$values=@{BOOST_ROOT=$boost;PLATFORM_TOOLSET='v143';VERSION_MAJOR=$Matches[1];VERSION_MINOR=$Matches[2];VERSION_PATCH=$Matches[3];PRODUCT_VERSION=$version;FILE_VERSION=$version}
foreach($key in $values.Keys){$properties=$properties.Replace(('$'+$key),$values[$key])}
[IO.File]::WriteAllText("$native/weasel.props",$properties,[Text.UTF8Encoding]::new($false))
$platforms=if($Architecture -eq 'both'){@('x64','Win32')}else{@($Architecture)}
foreach($platform in $platforms){
    $bits=if($platform -eq 'x64'){'64'}else{'32'}
    $arch=if($platform -eq 'x64'){'x64'}else{'x86'}
    $targets=if($platform -eq 'Win32'){'WeaselTSF'}else{'WeaselServer,WeaselTSF,WeaselDeployer'}
    $cmd=Join-Path $root "windows/build/native-$platform.cmd"
    New-Item -ItemType Directory -Path (Split-Path $cmd) -Force | Out-Null
    $content="@echo off`r`ncall `"$vs/VC/Auxiliary/Build/vcvars$bits.bat`"`r`nif errorlevel 1 exit /b 1`r`nset LIB=$root/.tools/windows-atl/lib/$arch;$root/.tools/boost-win$bits/lib;%LIB%`r`ncd /d `"$native`"`r`nmsbuild weasel.sln /m:4 /t:$targets /p:Configuration=Release /p:Platform=$platform /p:ZephyrArch=$arch /p:ZephyrBits=$bits /p:PlatformToolset=v143 /p:WindowsTargetPlatformVersion=10.0.22621.0 /verbosity:minimal /nologo`r`n"
    [IO.File]::WriteAllText($cmd,$content,[Text.UTF8Encoding]::new($false))
    & $cmd
    if($LASTEXITCODE){throw "$platform native build failed"}
}
