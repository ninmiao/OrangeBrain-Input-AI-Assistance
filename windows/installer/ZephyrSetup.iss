#ifndef Image
  #error Image required
#endif
#ifndef Version
  #define Version "1.9.1"
#endif
[Setup]
AppId={{EBA0B59B-4AD5-46C9-9F26-1C517208A753}
AppName=Zephyr Input
AppVersion={#Version}
AppPublisher=Zephyr Input
DefaultDirName={autopf}\Zephyr Input
UsePreviousAppDir=no
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableWelcomePage=no
DisableReadyPage=yes
PrivilegesRequired=admin
; x64compatible also admits Windows on ARM, which runs the x64/x86 TSF
; modules in emulated apps. InitializeSetup warns instead of blocking there.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#Output}
OutputBaseFilename=Zephyr-Input-Windows-{#Version}-Setup-x64
Compression=lzma2/fast
SolidCompression=yes
; Store file times in UTC. The default keeps the build machine's local time, so a
; cloud (UTC) build installed west of UTC got future-dated data files and Rime
; redeployed on every start ("Deployed" loop, no candidates).
TimeStampsInUTC=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no
SetupLogging=yes
UninstallDisplayIcon={app}\ZephyrSettings.exe
UninstallDisplayName=Zephyr Input
AppMutex=ZephyrInputSetupMutex
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
#ifdef ChineseMessages
Name: "chinesesimp"; MessagesFile: "{#ChineseMessages}"
#else
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
#endif
[CustomMessages]
english.Arm64Warning=This PC runs Windows on ARM. Support for it is experimental.%n%nThe keyboard module runs natively in ARM64 apps and in x64/x86 apps. The background service runs through Windows emulation, so the first start can be slow.%n%nContinue installing?
chinesesimp.Arm64Warning=当前电脑是 ARM64 版 Windows，对它的支持仍是实验性的。%n%n输入法模块在 ARM64 原生应用和 x64/x86 应用中都能加载；后台服务通过 Windows 兼容（仿真）模式运行，首次启动可能较慢。%n%n是否继续安装？
[Files]
Source: "{#Image}\*"; DestDir: "{app}"; Excludes: "ZephyrTSFx64.dll,ZephyrTSFx86.dll,ZephyrTSFarm64.dll,install.ps1,uninstall.ps1,Install.cmd,install.log,installation.json"; Flags: ignoreversion overwritereadonly recursesubdirs createallsubdirs uninsrestartdelete
Source: "{#Image}\ZephyrTSFx64.dll"; DestDir: "{app}"; DestName: "{#Dll64}"; Flags: ignoreversion overwritereadonly onlyifdoesntexist uninsrestartdelete
Source: "{#Image}\ZephyrTSFx86.dll"; DestDir: "{app}"; DestName: "{#Dll32}"; Flags: ignoreversion overwritereadonly onlyifdoesntexist uninsrestartdelete
; Windows on ARM: native ARM64 module plus the ARM64X forwarder that is registered.
; The forwarder sends ARM64 apps to {#DllArm64} and x64 apps to {#Dll64}.
Source: "{#Image}\ZephyrTSFarm64.dll"; DestDir: "{app}"; DestName: "{#DllArm64}"; Check: IsArm64; Flags: ignoreversion overwritereadonly onlyifdoesntexist uninsrestartdelete
Source: "{#Meta}\ZephyrTSFarm64x.dll"; DestDir: "{app}"; DestName: "{#DllArm64x}"; Check: IsArm64; Flags: ignoreversion overwritereadonly onlyifdoesntexist uninsrestartdelete
Source: "{#Meta}\installation.json"; DestDir: "{app}"; Flags: ignoreversion overwritereadonly
Source: "setup-helper.ps1"; DestDir: "{app}"; Flags: ignoreversion overwritereadonly; AfterInstall: RegisterIme
Source: "setup-helper.ps1"; Flags: dontcopy
[InstallDelete]
; These are the old jpackage-owned directories, never the user's AppData.
; PrepareToInstall validates the fixed installation root and stops its processes first.
Type: filesandordirs; Name: "{app}\runtime"
Type: filesandordirs; Name: "{app}\app"
[Registry]
Root: HKLM64; Subkey: "Software\ZephyrInput"; ValueType: string; ValueName: "WeaselRoot"; ValueData: "{app}"; Flags: uninsdeletekey
Root: HKLM32; Subkey: "Software\ZephyrInput"; ValueType: string; ValueName: "WeaselRoot"; ValueData: "{app}"; Flags: uninsdeletekey
[Icons]
Name: "{commonprograms}\Zephyr Input"; Filename: "{app}\ZephyrSettings.exe"; WorkingDir: "{app}"
Name: "{commonstartup}\Zephyr Input"; Filename: "{app}\ZephyrBroker.exe"; WorkingDir: "{app}"
[Run]
; The keyboard needs the broker after silent upgrades too.
Filename: "{app}\ZephyrBroker.exe"; Flags: nowait runasoriginaluser
Filename: "{app}\ZephyrSettings.exe"; Description: "Open Zephyr Input settings"; Flags: postinstall nowait runasoriginaluser skipifsilent
[UninstallDelete]
Type: files; Name: "{app}\install.ps1"
Type: files; Name: "{app}\uninstall.ps1"
Type: files; Name: "{app}\Install.cmd"
Type: files; Name: "{app}\install.log"
Type: files; Name: "{app}\1.5.0-digits.md"
Type: files; Name: "{app}\1.4.2-short-prompts.md"
Type: files; Name: "{app}\1.4.3-candidate-crash.md"
Type: dirifempty; Name: "{app}"
[Code]
var RestartNeeded: Boolean;
    DeploymentMutex: THandle;
function CreateMutex(Attributes: LongWord; InitialOwner: Boolean; Name: String): THandle;
 external 'CreateMutexW@kernel32.dll stdcall';
function CloseHandle(Handle: THandle): Boolean;
 external 'CloseHandle@kernel32.dll stdcall';
function InitializeSetup: Boolean;
begin
 DeploymentMutex:=CreateMutex(0,False,'ZephyrDeployerExclusiveMutex');Result:=DeploymentMutex<>0;
 // Warn only; silent installs continue (default answer IDYES).
 if Result and IsArm64 then
  Result:=SuppressibleMsgBox(CustomMessage('Arm64Warning'),mbConfirmation,MB_YESNO,IDYES)=IDYES;
end;
procedure DeinitializeSetup;
begin
 if DeploymentMutex<>0 then CloseHandle(DeploymentMutex);
end;
function InitializeUninstall: Boolean;
begin
 DeploymentMutex:=CreateMutex(0,False,'ZephyrDeployerExclusiveMutex');Result:=DeploymentMutex<>0;
end;
procedure DeinitializeUninstall;
begin
 if DeploymentMutex<>0 then CloseHandle(DeploymentMutex);
end;
function Helper(Script, Action: String): Boolean;
var Code: Integer;
begin
 Result := Exec(ExpandConstant('{sysnative}\WindowsPowerShell\v1.0\powershell.exe'),
  '-NoProfile -ExecutionPolicy Bypass -File "'+Script+'" -Action '+Action+' -Root "'+ExpandConstant('{app}')+'"',
  ExpandConstant('{sys}'), SW_HIDE, ewWaitUntilTerminated, Code) and ((Code=0) or (Code=3010));
 if Code=3010 then RestartNeeded:=True;
end;
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
 ExtractTemporaryFile('setup-helper.ps1');
 if not Helper(ExpandConstant('{tmp}\setup-helper.ps1'),'Stop') then Result := 'Cannot prepare the Zephyr Input update. Close its settings window and retry; the old runtime must be removable.';
end;
procedure RegisterIme;
begin
 if not Helper(ExpandConstant('{app}\setup-helper.ps1'),'Register') then RaiseException('Input method registration failed. Please run Setup again.');
end;
procedure CurUninstallStepChanged(Step: TUninstallStep);
begin
 if Step=usUninstall then begin

  if not Helper(ExpandConstant('{app}\setup-helper.ps1'),'Unregister') then begin
   SuppressibleMsgBox('Could not unregister the input method. No program files were removed. Run Setup to repair, then retry.',mbError,MB_OK,IDOK);Abort;
  end;
 end;
end;
function UninstallNeedRestart: Boolean;
begin
 Result := RestartNeeded;
end;
