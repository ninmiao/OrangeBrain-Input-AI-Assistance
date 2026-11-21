$ErrorActionPreference='Stop'
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(!$admin){Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -Wait -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'));exit}
$target=[IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'OrangeCell'))
if([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') -ne $target.TrimEnd('\')){throw 'Run the installed uninstaller from Program Files/OrangeCell.'}
$statePath=Join-Path $target 'installation.json'
$state=if(Test-Path -LiteralPath $statePath){Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json}else{@{x64='OrangeCellTSFx64.dll';x86='OrangeCellTSFx86.dll'}}
& "$target/OrangeCellServer.exe" /q
& "$env:WINDIR/System32/regsvr32.exe" /s /u (Join-Path $target $state.x64)
& "$env:WINDIR/SysWOW64/regsvr32.exe" /s /u (Join-Path $target $state.x86)
$prefix=$target.TrimEnd('\')+'\'
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { Stop-Process -Id $_.Id -Force }
foreach($folder in @([Environment]::GetFolderPath('CommonStartup'),[Environment]::GetFolderPath('CommonPrograms'))){$link=Join-Path $folder 'OrangeCell.lnk';if(Test-Path -LiteralPath $link){Remove-Item -LiteralPath $link}}
Write-Output 'OrangeCell unregistered. User dictionaries, settings and credentials are retained. Installed files can be removed after applications using the IME are closed.'
