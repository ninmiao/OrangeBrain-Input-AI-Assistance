param([switch]$Elevated)
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$admin=([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(!$admin){
    $child=Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-Elevated')
    if($child.ExitCode){throw "Elevated installation failed: $($child.ExitCode)"}
    Start-Process (Join-Path $env:ProgramFiles "OrangeCell/OrangeCellBroker.exe") -WindowStyle Hidden
    exit
}
if(![Environment]::Is64BitOperatingSystem){throw 'This package requires Windows x64'}
Start-Transcript -Path (Join-Path $PSScriptRoot 'install.log') -Force | Out-Null
$target=Join-Path $env:ProgramFiles 'OrangeCell'
$source=[IO.Path]::GetFullPath($PSScriptRoot)
if(!(Test-Path -LiteralPath "$source/OrangeCellTSFx64.dll")){throw 'Run install.ps1 from the packaged Windows image.'}
# Stop only this product's executables before replacing their native images.
$resolvedTarget=[IO.Path]::GetFullPath($target).TrimEnd('\')+'\'
$expected=[IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'OrangeCell')).TrimEnd('\')+'\'
if($resolvedTarget -ne $expected){throw 'Unexpected install target'}
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($resolvedTarget,[StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { Stop-Process -Id $_.Id -Force }
# Remove only the old jpackage-owned program directories, never AppData.
if((Test-Path -LiteralPath $target) -and ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Install target cannot be a reparse point'}
foreach($name in @('app','runtime')) {
    $old=[IO.Path]::GetFullPath((Join-Path $target $name))
    if([IO.Path]::GetDirectoryName($old).TrimEnd('\')+'\' -ne $resolvedTarget){throw 'Unexpected legacy runtime path'}
    if(Test-Path -LiteralPath $old) {
        if((Get-Item -LiteralPath $old).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Legacy runtime path cannot be a reparse point'}
        Remove-Item -LiteralPath $old -Recurse -Force
    }
}
# TSF DLLs stay loaded in Windows processes. Content-addressed names permit
# upgrading without replacing a mapped DLL or terminating unrelated apps.
$dlls=@{}
foreach($arch in @('x64','x86')) {
    $name="OrangeCellTSF$arch.dll"
    $digest=(Get-FileHash -LiteralPath (Join-Path $source $name) -Algorithm SHA256).Hash.Substring(0,12).ToLowerInvariant()
    $dlls[$arch]="OrangeCellTSF$arch-$digest.dll"
}
# Files are copied, never move or delete an existing project or user dictionary.
New-Item -ItemType Directory -Path $target -Force | Out-Null
Get-ChildItem -LiteralPath $source | Where-Object { $_.Name -notin @('OrangeCellTSFx64.dll','OrangeCellTSFx86.dll','install.log') } | Copy-Item -Destination $target -Recurse -Force
foreach($arch in @('x64','x86')) {
    $destination=Join-Path $target $dlls[$arch]
    if(!(Test-Path -LiteralPath $destination)){Copy-Item -LiteralPath (Join-Path $source "OrangeCellTSF$arch.dll") -Destination $destination}
}
foreach($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)){
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)
    $key=$base.CreateSubKey('Software\OrangeCell');$key.SetValue('WeaselRoot',$target);$key.Close();$base.Close()
}
& "$env:WINDIR/System32/regsvr32.exe" /s (Join-Path $target $dlls['x64'])
if($LASTEXITCODE){throw "x64 registration failed: $LASTEXITCODE"}
& "$env:WINDIR/SysWOW64/regsvr32.exe" /s (Join-Path $target $dlls['x86'])
if($LASTEXITCODE){throw "x86 registration failed: $LASTEXITCODE"}
$state=@{version='1.9.1';x64=$dlls['x64'];x86=$dlls['x86']}
[IO.File]::WriteAllText((Join-Path $target 'installation.json'),($state | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
$startup=Join-Path ([Environment]::GetFolderPath('CommonStartup')) 'OrangeCell.lnk'
$shell=New-Object -ComObject WScript.Shell
$link=$shell.CreateShortcut($startup);$link.TargetPath="$target/OrangeCellBroker.exe";$link.WorkingDirectory=$target;$link.Save()
$programs=Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'OrangeCell.lnk'
$link=$shell.CreateShortcut($programs);$link.TargetPath="$target/OrangeCellSettings.exe";$link.WorkingDirectory=$target;$link.Save()
Write-Output 'OrangeCell installed. Select OrangeCell in the Windows input-method menu. Existing input methods and user settings were retained.'

Stop-Transcript | Out-Null
