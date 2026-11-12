param([string]$Destination,[string]$Python='python')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if(!$Destination){$Destination=Join-Path $root 'dist/windows'}
$jdk=if($env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME/bin/jpackage.exe")){Get-Item "$env:JAVA_HOME/bin/jpackage.exe"}else{Get-ChildItem "$root/.tools/jdk/*/bin/jpackage.exe" -ErrorAction SilentlyContinue | Select-Object -First 1}
if(!$jdk){throw 'Set JAVA_HOME to JDK 17 with jpackage; see docs/DEVELOPMENT.md'}
$env:JAVA_HOME=Split-Path -Parent (Split-Path -Parent $jdk.FullName)
$native=Join-Path $root 'windows/native/output'
foreach($file in @('WeaselServer.exe','WeaselDeployer.exe','weaselx64.dll','weasel.dll','rime.dll')){if(!(Test-Path "$native/$file")){throw "Build native components first: missing $file"}}
& $Python "$PSScriptRoot/prepare-data.py"
if($LASTEXITCODE){throw 'Dictionary preparation failed'}
& "$root/gradlew.bat" -p "$root/windows" test installDist --console=plain
if($LASTEXITCODE){throw 'Windows JVM build failed'}
$image=Join-Path $Destination 'ZephyrSettings'
if(Test-Path -LiteralPath $image){throw "Output already exists: $image. Choose a fresh -Destination directory."}
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
$launcher=Join-Path $root 'windows/build/broker.properties'
[IO.File]::WriteAllText($launcher,"arguments=--broker`nwin-console=false`n",[Text.UTF8Encoding]::new($false))
& $jdk.FullName --type app-image --name ZephyrSettings --app-version 1.5.3 --vendor 'Zephyr Input' --description 'Zephyr Input for Windows' --dest $Destination --input "$root/windows/build/install/Zephyr-Windows/lib" --main-jar Zephyr-Windows.jar --main-class input.zephyr.windows.MainKt --add-launcher "ZephyrBroker=$launcher"
if($LASTEXITCODE){throw 'jpackage failed'}
foreach($pair in @(@('WeaselServer.exe','ZephyrServer.exe'),@('WeaselDeployer.exe','ZephyrDeployer.exe'),@('weaselx64.dll','ZephyrTSFx64.dll'),@('weasel.dll','ZephyrTSFx86.dll'),@('rime.dll','rime.dll'))){Copy-Item -LiteralPath (Join-Path $native $pair[0]) -Destination (Join-Path $image $pair[1])}
Copy-Item -LiteralPath "$native/data" -Destination "$image/data" -Recurse
Copy-Item -LiteralPath "$root/LICENSE" -Destination "$image/LICENSE.txt"
Copy-Item -LiteralPath "$root/windows/THIRD-PARTY.md" -Destination $image
Copy-Item -LiteralPath "$root/windows/README.md" -Destination $image
Copy-Item -LiteralPath "$root/docs/windows/VALIDATION.md" -Destination $image
Copy-Item -LiteralPath "$root/docs/windows/1.4.4-shortcuts.md" -Destination $image
$notices=Join-Path $image 'licenses';New-Item -ItemType Directory -Path $notices -Force | Out-Null
Copy-Item -LiteralPath "$root/windows/native/LICENSE.txt" -Destination "$notices/Weasel-GPL.txt"
Copy-Item -LiteralPath "$root/android/app/src/main/jni/boost/LICENSE_1_0.txt" -Destination "$notices/Boost.txt"
foreach($component in @('librime','OpenCC')){Copy-Item -LiteralPath "$root/android/app/src/main/jni/$component/LICENSE" -Destination "$notices/$component.txt"}
foreach($name in @('install.ps1','uninstall.ps1','Install.cmd','start_service.bat')){Copy-Item -LiteralPath "$PSScriptRoot/$name" -Destination $image}
Write-Output "Windows app image: $image"
