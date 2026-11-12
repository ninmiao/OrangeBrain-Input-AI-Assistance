param([Parameter(Mandatory=$true)][ValidateSet('Stop','Register','Unregister')][string]$Action,[Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
# Uninstall may inherit a temporary directory that no longer exists.
$stableDirectory=Join-Path $env:WINDIR 'System32'
Set-Location -LiteralPath $stableDirectory
[Environment]::CurrentDirectory=$stableDirectory
trap { [IO.File]::WriteAllText((Join-Path $env:TEMP 'Zephyr-setup-helper-error.log'),$_.Exception.ToString());exit 1 }
$target=[IO.Path]::GetFullPath($Root).TrimEnd('\')
$expected=[IO.Path]::GetFullPath((Join-Path ([Environment]::GetEnvironmentVariable('ProgramW6432')) 'Zephyr Input')).TrimEnd('\')
if($target -ne $expected){throw 'Unexpected installation directory'}
if(Test-Path -LiteralPath $target){
 if((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Installation directory cannot be a reparse point'}
}
$names=@('ZephyrBroker.exe','ZephyrServer.exe','ZephyrSettings.exe','ZephyrDeployer.exe')
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and [IO.Path]::GetDirectoryName($_.Path) -eq $target -and [IO.Path]::GetFileName($_.Path) -in $names } | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction Stop }
if($Action -eq 'Stop'){exit 0}
$state=Get-Content -LiteralPath (Join-Path $target 'installation.json') -Raw | ConvertFrom-Json
function Register-Dll([string]$name,[string]$arch,[bool]$remove) {
 if($name -notmatch '^ZephyrTSF(x64|x86)-[a-f0-9]{12}\.dll$'){throw 'Invalid DLL name'}
 $dll=Join-Path $target $name
 if(!(Test-Path -LiteralPath $dll)){if($remove){return};throw 'Missing TSF DLL'}
 $reg=Join-Path $env:WINDIR $(if($arch -eq 'x64'){'System32/regsvr32.exe'}else{'SysWOW64/regsvr32.exe'})
 $args=@('/s');if($remove){$args+='/u'};$args+='"'+$dll+'"'
 $p=Start-Process -FilePath $reg -ArgumentList $args -WindowStyle Hidden -Wait -PassThru
 if($p.ExitCode){throw "TSF $arch registration failed: $($p.ExitCode)"}
}
if($Action -eq 'Register') {
 # Reinstalling before reboot must not leave the active DLL queued for deletion.
 $sessionKey=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager',$true)
 try {
  $pending=@($sessionKey.GetValue('PendingFileRenameOperations',$null))
  if($pending.Count -gt 0 -and $pending.Count%2 -eq 0) {
   $keep=[Collections.Generic.List[string]]::new()
   $own=@((Join-Path $target $state.x64),(Join-Path $target $state.x86))
   for($i=0;$i -lt $pending.Count;$i+=2) {
    $src=$pending[$i] -replace '^\\\?\?\\',''
    if($src -in $own -and [string]::IsNullOrEmpty($pending[$i+1])){continue}
    $keep.Add($pending[$i]);$keep.Add($pending[$i+1])
   }
   if($keep.Count -eq 0){$sessionKey.DeleteValue('PendingFileRenameOperations',$false)}
   elseif($keep.Count -ne $pending.Count){$sessionKey.SetValue('PendingFileRenameOperations',$keep.ToArray(),[Microsoft.Win32.RegistryValueKind]::MultiString)}
  }
 } finally {$sessionKey.Close()}

 foreach($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {
  $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)
  try{$key=$base.CreateSubKey('Software\ZephyrInput');try{$key.SetValue('WeaselRoot',$target)}finally{$key.Close()}}finally{$base.Close()}
 }
 try {Register-Dll $state.x64 'x64' $false;Register-Dll $state.x86 'x86' $false}
 catch {try{Register-Dll $state.x64 'x64' $true;Register-Dll $state.x86 'x86' $true}catch{};throw}
} else {
 Register-Dll $state.x64 'x64' $true;Register-Dll $state.x86 'x86' $true
 foreach($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {
  $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)
  try{$base.DeleteSubKeyTree('Software\ZephyrInput',$false)}finally{$base.Close()}
 }
 # Only old product DLLs that preceded the tracked installer are cleaned here.
 Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class ZephyrRemove{[DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]public static extern bool MoveFileEx(string a,IntPtr b,int flags);}'
 Get-ChildItem -LiteralPath $target -File | Where-Object { $_.Name -match '^ZephyrTSF(x64|x86)(-[a-f0-9]{12})?\.dll$' } | ForEach-Object {
  $path=[IO.Path]::GetFullPath($_.FullName)
  if([IO.Path]::GetDirectoryName($path) -ne $target){throw 'Unexpected cleanup path'}
  try {Remove-Item -LiteralPath $path -Force -ErrorAction Stop} catch {
   if(![ZephyrRemove]::MoveFileEx($path,[IntPtr]::Zero,4)){throw ("Cannot schedule locked DLL removal: Win32="+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
   $script:restartNeeded=$true
  }
 }
 foreach($folder in @([Environment]::GetFolderPath('CommonStartup'),[Environment]::GetFolderPath('CommonPrograms'))){$link=Join-Path $folder 'Zephyr Input.lnk';if(Test-Path -LiteralPath $link){Remove-Item -LiteralPath $link -Force}}
}

if($script:restartNeeded){exit 3010}
