# Optional manual workflow for authorized samples and trusted installed tools.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Hermes','Unity')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$Tool,
    [Parameter(Mandatory=$true)][string]$InputFile,
    [string]$Metadata,
    [Parameter(Mandatory=$true)][string]$Parent
)
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path -LiteralPath $Tool).Path
$inputPath = (Resolve-Path -LiteralPath $InputFile).Path
$parentPath = (Resolve-Path -LiteralPath $Parent).Path
if (-not (Test-Path -LiteralPath $parentPath -PathType Container)) { throw 'Parent must be a directory.' }
if ((Get-Item -LiteralPath $inputPath).Length -gt 80MB) { throw 'Input exceeds 80 MiB.' }
if ($Mode -eq 'Hermes') {
    if ([IO.Path]::GetFileName($exe) -ine 'hbctool.exe') { throw 'Select trusted hbctool.exe.' }
} else {
    if ([IO.Path]::GetFileName($exe) -ine 'Il2CppDumper.exe') { throw 'Select trusted Il2CppDumper.exe.' }
    if (-not $Metadata) { throw 'Provide matching global-metadata.dat.' }
    $metaPath = (Resolve-Path -LiteralPath $Metadata).Path
    if ((Get-Item -LiteralPath $metaPath).Length -gt 80MB) { throw 'Metadata exceeds 80 MiB.' }
}
$session = Join-Path $parentPath ('droidre-framework-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $session | Out-Null
$out = Join-Path $session 'output'
Get-FileHash -LiteralPath $inputPath -Algorithm SHA256
if ($Mode -eq 'Hermes') {
    & $exe disasm $inputPath $out
} else {
    Get-FileHash -LiteralPath $metaPath -Algorithm SHA256
    New-Item -ItemType Directory -Path $out | Out-Null
    & $exe $inputPath $metaPath $out
}
$code = $LASTEXITCODE
Write-Host "Exit: $code. Output folder (may be partial): $out"
if ($code -ne 0) { throw 'External tool failed or does not support this input.' }
Write-Host 'Inspect recovered evidence; no compilation or runtime validation performed.'
