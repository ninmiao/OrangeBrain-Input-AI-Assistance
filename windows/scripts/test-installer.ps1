param([Parameter(Mandatory=$true)][string]$Setup,[string]$Report)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if(!$Report){$Report=Join-Path $root '.tools/installer-validation.json'}
$setupPath=(Resolve-Path -LiteralPath $Setup).Path
if([IO.Path]::GetFileName($setupPath) -notmatch '^Zephyr-Input-Windows-(?<version>[0-9]+\.[0-9]+\.[0-9]+)-Setup-x64\.exe$'){throw 'Unexpected installer'}
$expectedVersion=$Matches.version
$target=Join-Path $env:ProgramFiles 'Zephyr Input'
$uninstallKey='HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{EBA0B59B-4AD5-46C9-9F26-1C517208A753}_is1'
$data=Join-Path $env:APPDATA 'ZephyrInput'
$before=@{};if(Test-Path -LiteralPath $data){Get-ChildItem -LiteralPath $data -File | Where-Object {$_.Name -eq 'settings.json' -or $_.Name -like 'credential-*.bin'} | ForEach-Object {$before[$_.Name]=(Get-FileHash -LiteralPath $_.FullName).Hash}}
$checks=[Collections.Generic.List[string]]::new()
function Get-Uninstaller {
 if(!(Test-Path $uninstallKey)){throw 'Uninstall registry entry missing'}
 $command=(Get-ItemProperty $uninstallKey).UninstallString
 if($command -notmatch '^"([^"]+)"$'){throw 'Unexpected uninstall command'}
 $path=[IO.Path]::GetFullPath($Matches[1])
 if([IO.Path]::GetDirectoryName($path) -ne $target -or [IO.Path]::GetFileName($path) -notmatch '^unins[0-9]+\.exe$' -or !(Test-Path -LiteralPath $path)){throw 'Uninstaller missing or outside installation'}
 return $path
}
function Install-Check([string]$label) {
 $log=Join-Path $root ".tools/installer-$label.log"
 $p=Start-Process -FilePath $setupPath -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="'+$log+'"')) -WindowStyle Hidden -Wait -PassThru
 if($p.ExitCode -notin @(0,3010)){throw "Install failed: $($p.ExitCode)"}
 $state=Get-Content -LiteralPath "$target/installation.json" -Raw | ConvertFrom-Json
 if($state.version -ne $expectedVersion){throw 'Wrong installed version'}
 $null=Get-Uninstaller
 # A successful settings benchmark does not prove keyboard AI is available.
 # Silent installation must bring up the real per-user broker pipe as well.
 $deadline=[DateTime]::UtcNow.AddSeconds(15);$brokerReady=$false
 do {
  $probe=[IO.Pipes.NamedPipeClientStream]::new('.',('ZephyrAI-'+$env:USERNAME),[IO.Pipes.PipeDirection]::InOut)
  try {$probe.Connect(500);$brokerReady=$true} catch {} finally {$probe.Dispose()}
  if(!$brokerReady){Start-Sleep -Milliseconds 200}
 } while(!$brokerReady -and [DateTime]::UtcNow -lt $deadline)
 if(!$brokerReady){throw 'Installation completed but keyboard AI broker is not available'}
 $checks.Add($label+'-broker-ready')
 foreach($arch in @('x64','x86')){if(!(Test-Path -LiteralPath (Join-Path $target $state.$arch))){throw 'TSF DLL missing'}}
 if([version]$expectedVersion -ge [version]'1.9.0') {
  foreach($old in @('runtime','app')){if(Test-Path -LiteralPath (Join-Path $target $old)){throw 'Old JVM program directory remains after upgrade'}}
  $forbidden=Get-ChildItem -LiteralPath $target -Recurse -File | Where-Object {$_.Extension -in @('.jar','.class','.kt') -or $_.Name -in @('jvm.dll','java.exe','javaw.exe','jli.dll')}
  if($forbidden){throw 'JVM or Kotlin runtime remains after native upgrade'}
 }
 $checks.Add($label)
}
try {
 Install-Check 'upgrade'
 Install-Check 'same-version-update'
 $p=Start-Process -FilePath (Get-Uninstaller) -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="'+(Join-Path $root '.tools/installer-uninstall.log')+'"')) -WindowStyle Hidden -Wait -PassThru
 if($p.ExitCode -notin @(0,3010)){throw "Uninstall failed: $($p.ExitCode)"}
 if(Test-Path $uninstallKey){throw 'Uninstall registry entry remains'}
 if(Test-Path 'HKLM:\Software\ZephyrInput'){throw 'Product registry remains'}
 if(Test-Path -LiteralPath "$target/ZephyrSettings.exe"){throw 'Program remains after uninstall'}
 $checks.Add('uninstall')
 Install-Check 'reinstall'
 foreach($name in $before.Keys){if((Get-FileHash -LiteralPath (Join-Path $data $name)).Hash -ne $before[$name]){throw 'User config or credential changed'}}
 $checks.Add('user-data-preserved')
 $state=Get-Content -LiteralPath "$target/installation.json" -Raw | ConvertFrom-Json
 $pending=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue).PendingFileRenameOperations
 foreach($name in @($state.x64,$state.x86)){if($pending -and ($pending -join "`n").Contains($name)){throw 'Active DLL still pending deletion'}}
 $checks.Add('active-dll-not-pending-delete')
 @{passed=$true;checks=$checks.ToArray();version=$state.version}|ConvertTo-Json|Set-Content -LiteralPath $Report -Encoding UTF8
} catch {
 @{passed=$false;checks=$checks.ToArray();error=$_.Exception.Message}|ConvertTo-Json|Set-Content -LiteralPath $Report -Encoding UTF8
 throw
} finally {
 # Always restore a working installation, even if an uninstall assertion fails.
 if(!(Test-Path -LiteralPath "$target/ZephyrSettings.exe")){try{Install-Check 'recovery'}catch{}}
}
