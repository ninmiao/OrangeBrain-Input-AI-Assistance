#ifndef Image
  #error Image required
#endif
#ifndef Version
  #define Version "1.5.3"
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
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#Output}
OutputBaseFilename=Zephyr-Input-Windows-{#Version}-Setup-x64
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no
SetupLogging=yes
UninstallDisplayIcon={app}\ZephyrSettings.exe
UninstallDisplayName=Zephyr Input
AppMutex=ZephyrInputSetupMutex
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
[Files]
Source: "{#Image}\*"; DestDir: "{app}"; Excludes: "ZephyrTSFx64.dll,ZephyrTSFx86.dll,install.ps1,uninstall.ps1,Install.cmd,install.log,installation.json"; Flags: ignoreversion overwritereadonly recursesubdirs createallsubdirs uninsrestartdelete
Source: "{#Image}\ZephyrTSFx64.dll"; DestDir: "{app}"; DestName: "{#Dll64}"; Flags: ignoreversion overwritereadonly onlyifdoesntexist uninsrestartdelete
Source: "{#Image}\ZephyrTSFx86.dll"; DestDir: "{app}"; DestName: "{#Dll32}"; Flags: ignoreversion overwritereadonly onlyifdoesntexist uninsrestartdelete
Source: "{#Meta}\installation.json"; DestDir: "{app}"; Flags: ignoreversion overwritereadonly
Source: "setup-helper.ps1"; DestDir: "{app}"; Flags: ignoreversion overwritereadonly; AfterInstall: RegisterIme
Source: "setup-helper.ps1"; Flags: dontcopy
[Registry]
Root: HKLM64; Subkey: "Software\ZephyrInput"; ValueType: string; ValueName: "WeaselRoot"; ValueData: "{app}"; Flags: uninsdeletekey
Root: HKLM32; Subkey: "Software\ZephyrInput"; ValueType: string; ValueName: "WeaselRoot"; ValueData: "{app}"; Flags: uninsdeletekey
[Icons]
Name: "{commonprograms}\Zephyr Input"; Filename: "{app}\ZephyrSettings.exe"; WorkingDir: "{app}"
Name: "{commonstartup}\Zephyr Input"; Filename: "{app}\ZephyrBroker.exe"; WorkingDir: "{app}"
[Run]
Filename: "{app}\ZephyrBroker.exe"; Flags: nowait runasoriginaluser skipifsilent
Filename: "{app}\ZephyrSettings.exe"; Description: "Open Zephyr Input settings"; Flags: postinstall nowait runasoriginaluser skipifsilent
[UninstallDelete]
Type: files; Name: "{app}\install.ps1"
Type: files; Name: "{app}\uninstall.ps1"
Type: files; Name: "{app}\Install.cmd"
Type: files; Name: "{app}\install.log"
Type: files; Name: "{app}\1.4.1-digits.md"
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
 if not Helper(ExpandConstant('{tmp}\setup-helper.ps1'),'Stop') then Result := 'Cannot stop Zephyr Input. Close its settings window and retry.';
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
