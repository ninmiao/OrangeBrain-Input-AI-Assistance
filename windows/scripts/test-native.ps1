param([ValidateSet('x64','x86')][string]$Platform='x64',[switch]$Registered,[string]$InstalledPath)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$vswhere="${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$bits=if($Platform -eq 'x64'){'64'}else{'32'}
$out=Join-Path $root "windows/build/tests$bits"
New-Item -ItemType Directory -Path $out -Force | Out-Null
$cpp=Join-Path $root 'windows/tests/tsf_load_test.cpp'
$dll=if($bits -eq '64'){'weaselx64.dll'}else{'weasel.dll'}
$path=Join-Path $root "windows/native/output/$dll"
if($InstalledPath){
    $statePath=Join-Path $InstalledPath 'installation.json'
    if(Test-Path -LiteralPath $statePath){$state=Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json;$dll=if($bits -eq '64'){$state.x64}else{$state.x86}}
    else {$dll=if($bits -eq '64'){'ZephyrTSFx64.dll'}else{'ZephyrTSFx86.dll'}}
    $path=Join-Path $InstalledPath $dll
}
$flag=if($Registered){'--registered'}else{''}
$command="@echo off`r`ncall `"$vs/VC/Auxiliary/Build/vcvars$bits.bat`"`r`ncl /nologo /utf-8 /EHsc /std:c++17 /MT `"$cpp`" /Fe`"$out/tsf_load_test.exe`" /Fo`"$out/tsf_load_test.obj`" /link ole32.lib uuid.lib`r`nif errorlevel 1 exit /b 1`r`n`"$out/tsf_load_test.exe`" `"$path`" $flag`r`n"
$file=Join-Path $out 'run.cmd';[IO.File]::WriteAllText($file,$command,[Text.UTF8Encoding]::new($false));& $file
if($LASTEXITCODE){throw "TSF $bits-bit test failed"}
