# Builds the ARM64X pure-forwarder TSF module for Windows on ARM.
# ARM64 processes resolve its exports to the ARM64 module, x64 (emulated) processes
# to the x64 module. Targets are the installed, versioned file names, so the
# forwarder is generated per build (see windows/native/arm64x_wrapper).
param(
    [Parameter(Mandatory=$true)][string]$Arm64Target,
    [Parameter(Mandatory=$true)][string]$X64Target,
    [Parameter(Mandatory=$true)][string]$Output
)
$ErrorActionPreference='Stop'
foreach($name in @($Arm64Target,$X64Target)) {
    if($name -notmatch '^ZephyrTSF(arm64|x64)-[a-f0-9]{12}\.dll$'){throw "Invalid forward target: $name"}
}
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$vswhere="${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.ARM64EC -property installationPath
if(!$vs){throw 'The ARM64EC build tools are required for the ARM64X forwarder'}
$work=Join-Path $root 'windows/build/arm64x'
# Start clean: a library left by an interrupted run makes link fail with LNK1136.
if(Test-Path -LiteralPath $work){Remove-Item -LiteralPath $work -Recurse -Force}
New-Item -ItemType Directory -Force -Path $work | Out-Null
$exports=@('DllGetClassObject','DllCanUnloadNow','DllRegisterServer','DllUnregisterServer')
function Write-Def([string]$path,[string]$target) {
    $lines=@('EXPORTS')+($exports | ForEach-Object { "`t$_ = $target.$_" })
    [IO.File]::WriteAllLines($path,$lines,[Text.Encoding]::ASCII)
}
Write-Def "$work/arm64.def" $Arm64Target
Write-Def "$work/x64.def" $X64Target
Copy-Item -LiteralPath "$root/windows/native/arm64x_wrapper/dummy.c" -Destination "$work/dummy.c" -Force
$out=[IO.Path]::GetFullPath($Output)
$cmd=@(
    '@echo off'
    "call `"$vs/VC/Auxiliary/Build/vcvarsamd64_arm64.bat`" >nul"
    'if errorlevel 1 exit /b 1'
    "cd /d `"$work`""
    'cl /nologo /c /Fo:dummy_arm64.obj dummy.c || exit /b 1'
    'cl /nologo /c /arm64EC /Fo:dummy_x64.obj dummy.c || exit /b 1'
    'link /lib /nologo /machine:arm64 /def:arm64.def /out:arm64.lib /ignore:4104 || exit /b 1'
    'link /lib /nologo /machine:arm64ec /def:x64.def /out:x64.lib /ignore:4104 || exit /b 1'
    "link /nologo /dll /noentry /machine:arm64x /defArm64Native:arm64.def /def:x64.def /out:`"$out`" dummy_arm64.obj dummy_x64.obj arm64.lib x64.lib /ignore:4104 || exit /b 1"
)
$batch=Join-Path $work 'build.cmd'
[IO.File]::WriteAllLines($batch,$cmd,[Text.Encoding]::ASCII)
& cmd.exe /c $batch
if($LASTEXITCODE){throw 'ARM64X forwarder build failed'}
if(!(Test-Path -LiteralPath $out)){throw 'ARM64X forwarder was not produced'}
