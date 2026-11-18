param([Parameter(Mandatory=$true)][string]$Image,[string]$Version,[string]$Compiler,[string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Image=(Resolve-Path -LiteralPath $Image).Path
if(!$Version){$Version=(Get-Item -LiteralPath "$Image/ZephyrSettings.exe").VersionInfo.ProductVersion.Trim()}
if($Version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid installer version'}
if(!$Compiler){$Compiler=Join-Path $root '.tools/inno/ISCC.exe'}
if(!$OutputDirectory){$OutputDirectory=Join-Path $root 'dist'}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
if(!(Test-Path -LiteralPath $Compiler)){throw 'Install Inno Setup 6.7.1 or later and pass -Compiler path/to/ISCC.exe'}
$Compiler=(Resolve-Path -LiteralPath $Compiler).Path
$meta=Join-Path $root '.tools/setup-meta';New-Item -ItemType Directory -Force -Path $meta | Out-Null
$names=@{}
foreach($arch in @('x64','x86')) {
 $hash=(Get-FileHash -LiteralPath "$Image/ZephyrTSF$arch.dll" -Algorithm SHA256).Hash.Substring(0,12).ToLowerInvariant()
 $names[$arch]="ZephyrTSF$arch-$hash.dll"
}
$state=@{version=$Version;architecture='x64'}+ $names
[IO.File]::WriteAllText("$meta/installation.json",($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
$messages = Join-Path (Split-Path -Parent $Compiler) 'Languages/ChineseSimplified.isl'
if (!(Test-Path -LiteralPath $messages)) {
    $messages = Join-Path $meta 'ChineseSimplified-6.7.1.isl'
    $expected = '7D544B9BB1D142CFA11F2E5D3CC8ABE2E55F8E066C5124E3772675AA236E1278'
    if (!(Test-Path -LiteralPath $messages) -or (Get-FileHash -LiteralPath $messages).Hash -ne $expected) {
        $languageUrl = 'https://raw.githubusercontent.com/jrsoftware/issrc/cfdf48923178df4b4f040e038b423aa555a61ffc/Files/Languages/Unofficial/ChineseSimplified.isl'
        Invoke-WebRequest -UseBasicParsing -Uri $languageUrl -OutFile $messages
    }
    if ((Get-FileHash -LiteralPath $messages).Hash -ne $expected) { throw 'Inno Setup language file checksum mismatch' }
}
& $Compiler "/DChineseMessages=$messages" "/DImage=$Image" "/DVersion=$Version" "/DOutput=$OutputDirectory" "/DMeta=$meta" "/DDll64=$($names.x64)" "/DDll32=$($names.x86)" "$root/windows/installer/ZephyrSetup.iss"
if($LASTEXITCODE){throw 'Installer compilation failed'}
