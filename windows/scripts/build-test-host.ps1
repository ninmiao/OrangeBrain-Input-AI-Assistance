param([ValidateSet('x64','x86')][string]$Platform='x64')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$vs=& "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe" -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$bits=if($Platform -eq 'x64'){'64'}else{'32'}
$out=Join-Path $root "windows/build/ui-host-$Platform";New-Item -ItemType Directory -Path $out -Force | Out-Null
$cmd="@echo off`r`ncall `"$vs/VC/Auxiliary/Build/vcvars$bits.bat`"`r`ncd /d `"$out`"`r`ncl /nologo /utf-8 /EHsc /std:c++17 /MT `"$root/windows/tests/tsf_ui_host.cpp`" /Fetsf_ui_host.exe /link /SUBSYSTEM:WINDOWS user32.lib gdi32.lib ole32.lib uuid.lib`r`n"
[IO.File]::WriteAllText("$out/build-host.cmd",$cmd,[Text.UTF8Encoding]::new($false));& "$out/build-host.cmd"
if($LASTEXITCODE){throw 'TSF UI host build failed'}
Write-Output "UI host: $out/tsf_ui_host.exe"
