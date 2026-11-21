param(
    [string] $Output = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.tools\release-output'),
    [string] $Compiler
)
# One command for the local Windows release: dependencies, native x64 + x86 + ARM64 modules, tests,
# package, architecture check and the single x86 / x64 / ARM64 installer
# (OrangeCell-Windows-<version>-Setup-x86-arm64.exe) with its SHA256SUMS line.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root
$vsInstaller = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Microsoft Visual Studio/Installer'
$env:Path = "$vsInstaller;$env:Path"
function Step($name, [scriptblock] $block) {
    Write-Host "== $name"
    & $block
    if ($LASTEXITCODE) { throw "$name failed ($LASTEXITCODE)" }
}
Step 'Prepare native dependencies' { python windows/scripts/prepare-deps.py --reuse-boost }
Step 'Build native input service' { ./windows/scripts/build-native.ps1 }
Step 'Component tests' { ./windows/scripts/test-components.ps1 }
Step 'TSF x64 test' { ./windows/scripts/test-native.ps1 -Platform x64 }
Step 'TSF x86 test' { ./windows/scripts/test-native.ps1 -Platform x86 }
$image = Join-Path $root '.tools\release-image'
if (Test-Path $image) { Remove-Item -LiteralPath $image -Recurse -Force }
Step 'Package' { ./windows/scripts/package.ps1 -Destination $image }
$app = Join-Path $image 'OrangeCellSettings'
Step 'Architecture check' { python windows/scripts/verify-package.py $app }
if (!$Compiler) {
    $Compiler = (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source
    if (!$Compiler) {
        $Compiler = (Get-ChildItem "$root/.tools/inno*/ISCC.exe", "$root/.tools/inno/*/ISCC.exe", "${env:ProgramFiles(x86)}/Inno Setup */ISCC.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    }
}
if (!$Compiler) { throw 'Inno Setup compiler (ISCC.exe) not found' }
$version = (Get-Item (Join-Path $app 'OrangeCellSettings.exe')).VersionInfo.ProductVersion
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid Windows version: $version" }
if (Test-Path $Output) { Remove-Item -LiteralPath $Output -Recurse -Force }
Step 'Installer' { ./windows/scripts/build-installer.ps1 -Image $app -Version $version -Compiler $Compiler -OutputDirectory $Output }
$installer = Get-Item -LiteralPath (Join-Path $Output "OrangeCell-Windows-$version-Setup-x86-arm64.exe")
$digest = (Get-FileHash -LiteralPath $installer.FullName).Hash.ToLowerInvariant()
"$digest  $($installer.Name)" | Set-Content -LiteralPath (Join-Path $Output 'SHA256SUMS') -Encoding ASCII
Write-Host "Built $($installer.FullName)"
