param([switch]$Ipc,[string]$Corpus,[switch]$Live)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$vswhere="${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(!$vs){throw 'VS 2022 C++ Build Tools required'}
$out=Join-Path $root 'windows/build/tests';New-Item -ItemType Directory -Path $out -Force | Out-Null
$source=Join-Path $root 'windows/tests';$include=Join-Path $root 'windows/native/include'
$cmd="@echo off`r`ncall `"$vs/VC/Auxiliary/Build/vcvars64.bat`"`r`ncd /d `"$out`"`r`n"
$names=@('composition_test','text_range_test','shortcuts_test','stream_pipe_test','pipe_reconnect_test');if($Ipc){$names+=@('ipc_test','ai_pipe_test','raw_key_test')};if($Corpus){$names+='corpus_ipc_test'};if($Live){$names+='live_pipeline_test'}
foreach($name in $names){
    $libraries=if($name -in @('ipc_test','corpus_ipc_test','live_pipeline_test','raw_key_test','pipe_reconnect_test')){" `"$root/windows/native/msbuild/Release/x64/WeaselIPC.lib`""}else{''}
    $cmd+="cl /nologo /utf-8 /EHsc /std:c++17 /MT /D_WIN32_WINNT=0x0A00 /I`"$include`" /I`"$root/android/app/src/main/jni/boost`" `"$source/$name.cpp`"$libraries /Fe`"$out/$name.exe`" /Fo`"$out/$name.obj`" /link /LIBPATH:`"$root/.tools/boost-win64/lib`" user32.lib advapi32.lib shell32.lib ole32.lib`r`nif errorlevel 1 exit /b 1`r`n"
    $arg=if($name -eq 'corpus_ipc_test'){'"'+[IO.Path]::GetFullPath($Corpus)+'"'}else{''}
    $cmd+="`"$out/$name.exe`" $arg`r`nif errorlevel 1 exit /b 1`r`n"
}
# -Ipc requires the local Zephyr server and broker with cloud AI disabled.
$file=Join-Path $out 'components.cmd';[IO.File]::WriteAllText($file,$cmd,[Text.UTF8Encoding]::new($false));& $file
if($LASTEXITCODE){throw 'Native component test failed'}
