param([Parameter(Mandatory=$true)][string]$Image,[string]$Version='1.6.1',[string]$Compiler)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Image=(Resolve-Path -LiteralPath $Image).Path
if(!$Compiler){$Compiler=Join-Path $root '.tools/inno/ISCC.exe'}
if(!(Test-Path -LiteralPath $Compiler)){throw 'Install Inno Setup 7 and pass -Compiler path/to/ISCC.exe'}
$meta=Join-Path $root '.tools/setup-meta';New-Item -ItemType Directory -Force -Path $meta | Out-Null
$names=@{}
foreach($arch in @('x64','x86')) {
 $hash=(Get-FileHash -LiteralPath "$Image/ZephyrTSF$arch.dll" -Algorithm SHA256).Hash.Substring(0,12).ToLowerInvariant()
 $names[$arch]="ZephyrTSF$arch-$hash.dll"
}
$state=@{version=$Version;x64=$names.x64;x86=$names.x86}
[IO.File]::WriteAllText("$meta/installation.json",($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
& $Compiler "/DImage=$Image" "/DVersion=$Version" "/DOutput=$root/dist" "/DMeta=$meta" "/DDll64=$($names.x64)" "/DDll32=$($names.x86)" "$root/windows/installer/ZephyrSetup.iss"
if($LASTEXITCODE){throw 'Installer compilation failed'}
