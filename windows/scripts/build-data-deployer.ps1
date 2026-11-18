param([ValidateSet('x64','arm64')][string]$Architecture='x64')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$vswhere="${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs=& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(!$vs){throw 'Visual Studio C++ build tools are required.'}
$work=Join-Path $root $(if($Architecture -eq 'arm64'){'windows/build/data-deployer-arm64'}else{'windows/build/data-deployer'})
New-Item -ItemType Directory -Force -Path $work | Out-Null
$batch=Join-Path $work 'build.cmd'
$source=Join-Path $root 'windows/native/ZephyrDataDeploy.cpp'
$include=Join-Path $root 'windows/native/include'
$output=Join-Path $work 'ZephyrDataDeploy.exe'
$vcvars=if($Architecture -eq 'arm64'){'vcvarsamd64_arm64.bat'}else{'vcvars64.bat'}
$lines=@('@echo off',('call "'+$vs+'\VC\Auxiliary\Build\'+$vcvars+'" >nul'),'if errorlevel 1 exit /b 1',('cl /nologo /utf-8 /EHsc /std:c++17 /O2 /MT /I "'+$include+'" "'+$source+'" /Fe:"'+$output+'" /link /SUBSYSTEM:WINDOWS shell32.lib'), 'exit /b %errorlevel%')
[IO.File]::WriteAllLines($batch,$lines,[Text.Encoding]::ASCII)
Push-Location $work
try { & $batch; if($LASTEXITCODE){throw 'Data deployer build failed'} } finally {Pop-Location}
Write-Output $output
