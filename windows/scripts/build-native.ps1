param([ValidateSet('x64','Win32','ARM64','both')][string]$Architecture='both')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$vswhere="${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(!$vs){throw 'Visual Studio 2022 C++ Build Tools required; see docs/DEVELOPMENT.md'}
$boost=Join-Path $root 'android/app/src/main/jni/boost'
if(!(Test-Path "$boost/boost")){throw 'Prepare Boost headers/libraries first: windows/scripts/prepare-deps.py'}
$native=Join-Path $root 'windows/native'
$properties=[IO.File]::ReadAllText("$native/weasel.props.template")
$values=@{BOOST_ROOT=$boost;PLATFORM_TOOLSET='v143';VERSION_MAJOR='1';VERSION_MINOR='10';VERSION_PATCH='0';PRODUCT_VERSION='1.10.0.0';FILE_VERSION='1.10.0.0'}
foreach($key in $values.Keys){$properties=$properties.Replace(('$'+$key),$values[$key])}
[IO.File]::WriteAllText("$native/weasel.props",$properties,[Text.UTF8Encoding]::new($false))
$platforms=if($Architecture -eq 'both'){@('x64','Win32')}else{@($Architecture)}
foreach($platform in $platforms){
    $bits=@{x64='64';Win32='32';ARM64='arm64'}[$platform]
    $arch=@{x64='x64';Win32='x86';ARM64='arm64'}[$platform]
    $vcvars=@{x64='vcvars64.bat';Win32='vcvars32.bat';ARM64='vcvarsamd64_arm64.bat'}[$platform]
    $targets=if($platform -eq 'Win32'){'WeaselTSF'}else{'WeaselServer,WeaselTSF,WeaselDeployer'}
    $cmd=Join-Path $root "windows/build/native-$platform.cmd"
    New-Item -ItemType Directory -Path (Split-Path $cmd) -Force | Out-Null
    $content="@echo off`r`ncall `"$vs/VC/Auxiliary/Build/$vcvars`"`r`nif errorlevel 1 exit /b 1`r`nset LIB=$root/.tools/windows-atl/lib/$arch;$root/.tools/boost-win$bits/lib;%LIB%`r`ncd /d `"$native`"`r`nmsbuild weasel.sln /m:4 /t:$targets /p:Configuration=Release /p:Platform=$platform /p:ZephyrArch=$arch /p:ZephyrBits=$bits /p:PlatformToolset=v143 /p:WindowsTargetPlatformVersion=10.0.22621.0 /verbosity:minimal /nologo`r`n"
    [IO.File]::WriteAllText($cmd,$content,[Text.UTF8Encoding]::new($false))
    & $cmd
    if($LASTEXITCODE){throw "$platform native build failed"}
}
