param([string]$Destination,[string]$Python='python')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if(!$Destination){$Destination=Join-Path $root 'dist/windows'}
$native=Join-Path $root 'windows/native/output'
foreach($file in @('WeaselServer.exe','WeaselDeployer.exe','weaselx64.dll','weasel.dll','rime.dll')) {
 if(!(Test-Path "$native/$file")){throw "Build native components first: missing $file"}
}
& "$PSScriptRoot/build-app.ps1"
& "$PSScriptRoot/build-data-deployer.ps1"
& $Python "$PSScriptRoot/prepare-data.py"
if($LASTEXITCODE){throw 'Dictionary preparation failed'}
$image=Join-Path $Destination 'ZephyrSettings'
if(Test-Path -LiteralPath $image){throw "Output already exists: $image. Choose a fresh -Destination directory."}
New-Item -ItemType Directory -Path $image -Force | Out-Null
foreach($name in @('ZephyrSettings.exe','ZephyrBroker.exe')) {
 Copy-Item -LiteralPath "$root/windows/build/native-app/Release/$name" -Destination $image
}
foreach($pair in @(@('WeaselServer.exe','ZephyrServer.exe'),@('WeaselDeployer.exe','ZephyrDeployer.exe'),@('weaselx64.dll','ZephyrTSFx64.dll'),@('weasel.dll','ZephyrTSFx86.dll'),@('rime.dll','rime.dll'))) {
 Copy-Item -LiteralPath (Join-Path $native $pair[0]) -Destination (Join-Path $image $pair[1])
}
Copy-Item -LiteralPath "$root/windows/build/data-deployer/ZephyrDataDeploy.exe" -Destination $image
Copy-Item -LiteralPath "$native/data" -Destination "$image/data" -Recurse
New-Item -ItemType Directory -Path "$image/resources" -Force | Out-Null
Copy-Item -LiteralPath "$root/shared/ai-core/src/main/resources/rime" -Destination "$image/resources/rime" -Recurse
Copy-Item -LiteralPath "$root/LICENSE" -Destination "$image/LICENSE.txt"
Copy-Item -LiteralPath "$root/windows/THIRD-PARTY.md" -Destination $image
Copy-Item -LiteralPath "$root/windows/README.md" -Destination $image
$notices=Join-Path $image 'licenses'
New-Item -ItemType Directory -Path $notices -Force | Out-Null
Copy-Item -LiteralPath "$root/shared/ai-core/src/main/resources/rime/wanxiang-CC-BY-4.0.txt" -Destination "$notices/Wanxiang-CC-BY-4.0.txt"
Copy-Item -LiteralPath "$root/shared/native-core/third_party/nlohmann/LICENSE.MIT" -Destination "$notices/nlohmann-json-MIT.txt"
Copy-Item -LiteralPath "$root/windows/app/third_party/miniz/LICENSE" -Destination "$notices/miniz-MIT.txt"
Copy-Item -LiteralPath "$root/windows/native/LICENSE.txt" -Destination "$notices/Weasel-GPL.txt"
Copy-Item -LiteralPath "$root/android/app/src/main/jni/boost/LICENSE_1_0.txt" -Destination "$notices/Boost.txt"
foreach($component in @('librime','OpenCC')) { Copy-Item -LiteralPath "$root/android/app/src/main/jni/$component/LICENSE" -Destination "$notices/$component.txt" }
foreach($name in @('install.ps1','uninstall.ps1','Install.cmd','start_service.bat')) { Copy-Item -LiteralPath "$PSScriptRoot/$name" -Destination $image }
$forbidden=Get-ChildItem -LiteralPath $image -Recurse -File | Where-Object { $_.Extension -in @('.jar','.class','.kt') -or $_.Name -in @('jvm.dll','java.exe','javaw.exe','jli.dll') }
if($forbidden){throw 'Unexpected JVM or Kotlin artifact in native package'}
Write-Output "Native Windows image (no JVM/JDK required): $image"
