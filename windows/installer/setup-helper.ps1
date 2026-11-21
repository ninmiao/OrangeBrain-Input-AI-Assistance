param([Parameter(Mandatory=$true)][ValidateSet('Stop','Register','Unregister')][string]$Action,[Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
# Uninstall may inherit a temporary directory that no longer exists.
$stableDirectory=Join-Path $env:WINDIR 'System32'
Set-Location -LiteralPath $stableDirectory
[Environment]::CurrentDirectory=$stableDirectory
trap { [IO.File]::WriteAllText((Join-Path $env:TEMP 'OrangeCell-setup-helper-error.log'),$_.Exception.ToString());exit 1 }
$target=[IO.Path]::GetFullPath($Root).TrimEnd('\')
$expected=[IO.Path]::GetFullPath((Join-Path ([Environment]::GetEnvironmentVariable('ProgramW6432')) 'OrangeCell')).TrimEnd('\')
if($target -ne $expected){throw 'Unexpected installation directory'}
if(Test-Path -LiteralPath $target){
 if((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Installation directory cannot be a reparse point'}
}
$names=@('OrangeCellBroker.exe','OrangeCellServer.exe','OrangeCellSettings.exe','OrangeCellDeployer.exe')
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and [IO.Path]::GetDirectoryName($_.Path) -eq $target -and [IO.Path]::GetFileName($_.Path) -in $names } | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction Stop }
if($Action -eq 'Stop'){
 # Remove the previous jpackage runtime before copying the native application.
 # Do not rely on InstallDelete: fail the upgrade if old runtime files remain.
 foreach($name in @('app','runtime')) {
  $legacy=[IO.Path]::GetFullPath((Join-Path $target $name))
  if([IO.Path]::GetDirectoryName($legacy) -ne $target){throw 'Unexpected legacy directory'}
  if(!(Test-Path -LiteralPath $legacy)){continue}
  $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($legacy)
  while($pending.Count -gt 0) {
   $current=$pending.Pop();$item=Get-Item -LiteralPath $current -Force
   if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Legacy directory contains a reparse point'}
   if($item.PSIsContainer){
    foreach($child in Get-ChildItem -LiteralPath $current -Force) {
     $childPath=[IO.Path]::GetFullPath($child.FullName)
     if(!$childPath.StartsWith($legacy+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Legacy cleanup path escaped its directory'}
     $pending.Push($childPath)
    }
   }
  }
  Remove-Item -LiteralPath $legacy -Recurse -Force -ErrorAction Stop
  if(Test-Path -LiteralPath $legacy){throw 'Legacy runtime cleanup did not finish'}
 }
 exit 0
}
$state=Get-Content -LiteralPath (Join-Path $target 'installation.json') -Raw | ConvertFrom-Json
if($state.architecture -and $state.architecture -ne 'x64'){throw 'Invalid installation architecture'}
# The system value, not this process: Setup itself may run emulated on Windows on ARM.
$machine=(Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment').PROCESSOR_ARCHITECTURE
# 64-bit view: the x64 module on x64 PCs; on Windows on ARM the ARM64X forwarder,
# which sends ARM64 apps to the ARM64 module and x64 apps to the x64 module.
$architectures=if($machine -eq 'ARM64'){@('arm64x','x86')}else{@('x64','x86')}
$clsid='{7A61AC12-AF2D-4810-895E-09DB95C0D3B2}'
$views=@([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)
function Register-Dll([string]$name,[string]$arch,[bool]$remove) {
 if($remove -and [string]::IsNullOrEmpty($name)){return}
 if($name -notmatch ('^OrangeCellTSF'+$arch+'-[a-f0-9]{12}\.dll$')){throw 'Invalid DLL name'}
 $dll=Join-Path $target $name
 if(!(Test-Path -LiteralPath $dll)){if($remove){return};throw 'Missing TSF DLL'}
 if($arch -eq 'arm64x' -and !$remove) {
  foreach($forwarded in @($state.arm64,$state.x64)) {
   if([string]::IsNullOrEmpty($forwarded) -or !(Test-Path -LiteralPath (Join-Path $target $forwarded))){throw 'Missing ARM64X forward target'}
  }
 }
 $reg=Join-Path $env:WINDIR $(if($arch -eq 'x86'){'SysWOW64/regsvr32.exe'}else{'System32/regsvr32.exe'})
 $args=@('/s');if($remove){$args+='/u'};$args+='"'+$dll+'"'
 $p=Start-Process -FilePath $reg -ArgumentList $args -WindowStyle Hidden -Wait -PassThru
 if($p.ExitCode){throw "TSF $arch registration failed: $($p.ExitCode)"}
 if($arch -eq 'arm64x' -and !$remove) {
  # Registration ran inside the ARM64 module and wrote its own path. COM must load
  # the forwarder instead, or x64 apps could not load the input method.
  $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
  try {
   $key=$base.OpenSubKey("SOFTWARE\Classes\CLSID\$clsid\InprocServer32",$true)
   if(!$key){throw 'TSF server was not registered'}
   try{$key.SetValue('',$dll)}finally{$key.Close()}
  } finally {$base.Close()}
 }
}
if($Action -eq 'Register') {
 # Reinstalling before reboot must not leave the active DLL queued for deletion.
 $sessionKey=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager',$true)
 try {
  $pending=@($sessionKey.GetValue('PendingFileRenameOperations',$null))
  if($pending.Count -gt 0 -and $pending.Count%2 -eq 0) {
   $keep=[Collections.Generic.List[string]]::new()
   $own=@(@('x64','x86','arm64','arm64x') | Where-Object { $state.$_ } | ForEach-Object {Join-Path $target $state.$_})
   for($i=0;$i -lt $pending.Count;$i+=2) {
    $src=$pending[$i] -replace '^\\\?\?\\',''
    if($src -in $own -and [string]::IsNullOrEmpty($pending[$i+1])){continue}
    $keep.Add($pending[$i]);$keep.Add($pending[$i+1])
   }
   if($keep.Count -eq 0){$sessionKey.DeleteValue('PendingFileRenameOperations',$false)}
   elseif($keep.Count -ne $pending.Count){$sessionKey.SetValue('PendingFileRenameOperations',$keep.ToArray(),[Microsoft.Win32.RegistryValueKind]::MultiString)}
  }
 } finally {$sessionKey.Close()}

 foreach($view in $views) {
  $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)
  try{$key=$base.CreateSubKey('Software\OrangeCell');try{$key.SetValue('WeaselRoot',$target)}finally{$key.Close()}}finally{$base.Close()}
 }
 $registered=@()
 try {
  foreach($arch in $architectures){Register-Dll $state.$arch $arch $false;$registered+=$arch}
 } catch {
  foreach($arch in $registered){try{Register-Dll $state.$arch $arch $true}catch{}}
  throw
 }
} else {
 foreach($arch in $architectures){Register-Dll $state.$arch $arch $true}
 foreach($view in $views) {
  $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)
  try{$base.DeleteSubKeyTree('Software\OrangeCell',$false)}finally{$base.Close()}
 }
 # Only old product DLLs that preceded the tracked installer are cleaned here.
 Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class OrangeCellRemove{[DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]public static extern bool MoveFileEx(string a,IntPtr b,int flags);}'
 Get-ChildItem -LiteralPath $target -File | Where-Object { $_.Name -match '^OrangeCellTSF(x64|x86|arm64|arm64x)(-[a-f0-9]{12})?\.dll$' } | ForEach-Object {
  $path=[IO.Path]::GetFullPath($_.FullName)
  if([IO.Path]::GetDirectoryName($path) -ne $target){throw 'Unexpected cleanup path'}
  try {Remove-Item -LiteralPath $path -Force -ErrorAction Stop} catch {
   if(![OrangeCellRemove]::MoveFileEx($path,[IntPtr]::Zero,4)){throw ("Cannot schedule locked DLL removal: Win32="+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
   $script:restartNeeded=$true
  }
 }
 foreach($folder in @([Environment]::GetFolderPath('CommonStartup'),[Environment]::GetFolderPath('CommonPrograms'))){$link=Join-Path $folder 'OrangeCell.lnk';if(Test-Path -LiteralPath $link){Remove-Item -LiteralPath $link -Force}}
}

if($script:restartNeeded){exit 3010}
