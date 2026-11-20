# Builds the ARM64X TSF loader for Windows on ARM (windows/native/arm64x_wrapper/forwarder.c).
# Its ARM64 half serves native ARM64 apps with the ARM64 module, its ARM64EC half serves
# emulated x64 apps with the x64 module. Each half loads its target by full path from
# the loader's own folder. The targets are the installed, versioned file names, so the
# loader is generated per build.
param(
    [Parameter(Mandatory=$true)][string]$Arm64Target,
    [Parameter(Mandatory=$true)][string]$X64Target,
    [Parameter(Mandatory=$true)][string]$Output
)
$ErrorActionPreference='Stop'
foreach($name in @($Arm64Target,$X64Target)) {
    if($name -notmatch '^ZephyrTSF(arm64|x64)-[a-f0-9]{12}\.dll$'){throw "Invalid loader target: $name"}
}
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$vswhere="${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.ARM64EC -property installationPath
if(!$vs){throw 'The ARM64EC build tools are required for the ARM64X loader'}
$work=Join-Path $root 'windows/build/arm64x'
# Start clean: a library left by an interrupted run makes link fail with LNK1136.
if(Test-Path -LiteralPath $work){Remove-Item -LiteralPath $work -Recurse -Force}
New-Item -ItemType Directory -Force -Path $work | Out-Null
$arm64Header=Join-Path $work 'arm64_target.h'
$x64Header=Join-Path $work 'x64_target.h'
[IO.File]::WriteAllText($arm64Header,"#define ZEPHYR_TARGET `"$Arm64Target`"`r`n",[Text.Encoding]::ASCII)
[IO.File]::WriteAllText($x64Header,"#define ZEPHYR_TARGET `"$X64Target`"`r`n",[Text.Encoding]::ASCII)
$exports=@('EXPORTS')+(@('DllGetClassObject','DllCanUnloadNow','DllRegisterServer','DllUnregisterServer') | ForEach-Object { "`t$_ PRIVATE" })
[IO.File]::WriteAllLines((Join-Path $work 'exports.def'),$exports,[Text.Encoding]::ASCII)
$source=Join-Path $root 'windows/native/arm64x_wrapper/forwarder.c'
$out=[IO.Path]::GetFullPath($Output)
# Static CRT: the ARM64EC half needs its dispatch helpers and load configuration.
$flags='/nologo /c /O1 /MT /W3 /WX'
$cmd=@(
    '@echo off'
    "call `"$vs/VC/Auxiliary/Build/vcvarsamd64_arm64.bat`" >nul"
    'if errorlevel 1 exit /b 1'
    "cd /d `"$work`""
    "cl $flags /FI`"$arm64Header`" /Fo:loader_arm64.obj `"$source`" || exit /b 1"
    "cl $flags /arm64EC /FI`"$x64Header`" /Fo:loader_x64.obj `"$source`" || exit /b 1"
    "link /nologo /dll /machine:arm64x /defArm64Native:exports.def /def:exports.def /out:`"$out`" loader_arm64.obj loader_x64.obj kernel32.lib || exit /b 1"
)
$batch=Join-Path $work 'build.cmd'
[IO.File]::WriteAllLines($batch,$cmd,[Text.Encoding]::ASCII)
& cmd.exe /c $batch
if($LASTEXITCODE){throw 'ARM64X loader build failed'}
if(!(Test-Path -LiteralPath $out)){throw 'ARM64X loader was not produced'}
