$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$release = (Resolve-Path 'build/windows/x64/runner/Release').Path
if (-not (Test-Path (Join-Path $release 'droidre_ai_studio.exe') -PathType Leaf)) { throw 'Windows executable not found.' }
if (-not (Test-Path (Join-Path $release 'data/flutter_assets') -PathType Container)) { throw 'Flutter assets not found.' }
$pf86 = [Environment]::GetFolderPath('ProgramFilesX86')
$vswhere = Join-Path $pf86 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Visual Studio C++ installation not found.' }
$crt = Get-ChildItem (Join-Path $vs 'VC/Redist/MSVC') -Directory |
    Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending |
    ForEach-Object { Join-Path $_.FullName 'x64/Microsoft.VC143.CRT' } |
    Where-Object { Test-Path $_ -PathType Container } | Select-Object -First 1
if (-not $crt) { throw 'Visual C++ redistributable CRT directory not found.' }
Copy-Item (Join-Path $crt '*.dll') $release -Force
foreach ($dll in @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll', 'flutter_windows.dll')) {
    if (-not (Test-Path (Join-Path $release $dll))) { throw "Missing runtime file $dll" }
}
$dist = Join-Path (Get-Location) 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
Compress-Archive -Path (Join-Path $release '*') -DestinationPath (Join-Path $dist 'DroidRE-AI-Studio-x64-Portable.zip') -Force
$iscc = Join-Path $pf86 'Inno Setup 6\ISCC.exe'
if (-not (Test-Path $iscc)) { $iscc = (Get-Command ISCC.exe -ErrorAction Stop).Source }
$versionLine = Get-Content pubspec.yaml | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1
$version = (($versionLine -replace '^version:\s*', '') -split '\+')[0].Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid installer version.' }
& $iscc "/DAppVersion=$version" 'installer/droidre.iss'
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compiler failed.' }
if (-not (Test-Path (Join-Path $dist 'DroidRE-AI-Studio-x64-Setup.exe') -PathType Leaf)) { throw 'Installer not found.' }
Get-ChildItem $dist -File | Where-Object { $_.Extension -in '.zip', '.exe' } |
    ForEach-Object { "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Name } |
    Set-Content (Join-Path $dist 'SHA256SUMS.txt') -Encoding ascii
