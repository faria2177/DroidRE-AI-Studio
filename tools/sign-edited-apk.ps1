# Requires Android SDK Build Tools 35+ and an authorized signing key.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$UnsignedApk,
    [Parameter(Mandatory=$true)][string]$OutputApk,
    [Parameter(Mandatory=$true)][string]$BuildToolsDir,
    [Parameter(Mandatory=$true)][string]$Keystore,
    [Parameter(Mandatory=$true)][string]$Alias
)
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $UnsignedApk).Path
$key = (Resolve-Path -LiteralPath $Keystore).Path
$tools = (Resolve-Path -LiteralPath $BuildToolsDir).Path
$output = [IO.Path]::GetFullPath($OutputApk)
if ($source -eq $output -or (Test-Path -LiteralPath $output)) {
    throw 'Choose a new output APK; existing files are never overwritten.'
}
$aligner = Join-Path $tools 'zipalign.exe'
$signer = Join-Path $tools 'apksigner.bat'
foreach ($tool in @($aligner, $signer)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing SDK tool: $tool" }
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ("droidre-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $aligned = Join-Path $temp 'aligned.apk'
    $signed = Join-Path $temp 'signed.apk'
    & $aligner -P 16 -f 4 $source $aligned
    if ($LASTEXITCODE -ne 0) { throw 'zipalign failed.' }
    & $signer sign --ks $key --ks-key-alias $Alias --out $signed $aligned
    if ($LASTEXITCODE -ne 0) { throw 'Signing failed.' }
    & $signer verify --verbose --print-certs $signed
    if ($LASTEXITCODE -ne 0) { throw 'Signature verification failed.' }
    & $aligner -c -P 16 4 $signed
    if ($LASTEXITCODE -ne 0) { throw 'Alignment verification failed.' }
    [IO.File]::Copy($signed, $output, $false)
    Get-FileHash -LiteralPath $output -Algorithm SHA256
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}
