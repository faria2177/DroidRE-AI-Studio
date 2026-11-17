#ifndef AppVersion
#define AppVersion "0.7.0"
#endif
[Setup]
AppId=DroidRE-AI-Studio
AppName=DroidRE AI Studio
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\DroidRE AI Studio
DefaultGroupName=DroidRE AI Studio
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\dist
OutputBaseFilename=DroidRE-AI-Studio-x64-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\droidre_ai_studio.exe
CloseApplications=yes
[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
[Icons]
Name: "{group}\DroidRE AI Studio"; Filename: "{app}\droidre_ai_studio.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\DroidRE AI Studio"; Filename: "{app}\droidre_ai_studio.exe"; WorkingDir: "{app}"; Tasks: desktopicon
[Run]
Filename: "{app}\droidre_ai_studio.exe"; Description: "Launch DroidRE AI Studio"; Flags: nowait postinstall skipifsilent
