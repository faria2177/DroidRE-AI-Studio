# Local owner-controlled build. Never commits or uploads signing material.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Keystore,
    [Parameter(Mandatory=$true)][string]$Alias,
    [Parameter(Mandatory=$true)][string]$BuildToolsDir,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedCertSha256,
    [Parameter(Mandatory=$true)][string]$OutputParent
)
$ErrorActionPreference = 'Stop'
$key = (Resolve-Path -LiteralPath $Keystore).Path
$parent = (Resolve-Path -LiteralPath $OutputParent).Path
$signer = Join-Path (Resolve-Path -LiteralPath $BuildToolsDir).Path 'apksigner.bat'
if (-not (Test-Path -LiteralPath $key -PathType Leaf)) { throw 'Keystore not found.' }
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Output parent must be a folder.' }
if (-not (Test-Path -LiteralPath $signer -PathType Leaf)) { throw 'apksigner.bat not found.' }
if ([IO.Path]::GetFileName($key) -ieq 'debug.keystore' -or $Alias -ieq 'androiddebugkey') {
    throw 'Debug signing credentials cannot be used.'
}
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ($key.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Keep the owner keystore outside this repository.'
}
$names = @('DROIDRE_PRODUCTION_SIGNING','DROIDRE_KEYSTORE','DROIDRE_KEY_ALIAS',
    'DROIDRE_STORE_PASSWORD','DROIDRE_KEY_PASSWORD')
$previous = @{}
foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$store = Read-Host 'Keystore password' -AsSecureString
$secret = Read-Host 'Key password' -AsSecureString
$entered = $false
try {
    $env:DROIDRE_PRODUCTION_SIGNING = '1'
    $env:DROIDRE_KEYSTORE = $key
    $env:DROIDRE_KEY_ALIAS = $Alias
    $env:DROIDRE_STORE_PASSWORD = [System.Net.NetworkCredential]::new('', $store).Password
    $env:DROIDRE_KEY_PASSWORD = [System.Net.NetworkCredential]::new('', $secret).Password
    Push-Location $root
    $entered = $true
    function Invoke-Flutter([string[]]$Arguments) {
        & flutter @Arguments
        if ($LASTEXITCODE -ne 0) { throw "Flutter failed: $($Arguments[0])" }
    }
    Invoke-Flutter @('pub','get')
    Invoke-Flutter @('analyze')
    Invoke-Flutter @('test')
    Invoke-Flutter @('build','apk','--release','--split-per-abi')
    Invoke-Flutter @('build','appbundle','--release')
    $apks = @(Get-ChildItem 'build/app/outputs/flutter-apk/*-release.apk' -File)
    foreach ($required in @('app-arm64-v8a-release.apk','app-armeabi-v7a-release.apk')) {
        if (-not ($apks.Name -contains $required)) { throw "Missing ABI artifact: $required" }
    }
    $bundle = Get-Item 'build/app/outputs/bundle/release/app-release.aab'
    $expected = $ExpectedCertSha256.ToLowerInvariant()
    foreach ($apk in $apks) {
        $verification = @(& $signer verify --verbose --print-certs $apk.FullName 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed: $($apk.Name)" }
        $certs = @($verification | ForEach-Object {
            if ("$_" -match '^Signer #\d+ certificate SHA-256 digest:\s*([0-9a-fA-F]{64})\s*$') {
                $Matches[1].ToLowerInvariant()
            }
        })
        if ($certs.Count -ne 1 -or $certs[0] -ne $expected) {
            throw "Unexpected APK signing certificate: $($apk.Name)"
        }
    }
    # Read every non-signature bundle payload and validate its leaf signer.
    & java (Join-Path $root 'tools/VerifyBundleSigners.java') $bundle.FullName $expected
    if ($LASTEXITCODE -ne 0) { throw 'AAB payload/signing certificate verification failed.' }
    $dest = Join-Path $parent ('droidre-owner-release-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dest | Out-Null
    foreach ($artifact in @($apks) + @($bundle)) {
        [IO.File]::Copy($artifact.FullName, (Join-Path $dest $artifact.Name), $false)
    }
    Get-ChildItem -LiteralPath $dest -File | ForEach-Object {
        "{0}  {1}" -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $_.Name
    } | Set-Content -LiteralPath (Join-Path $dest 'SHA256SUMS.txt') -Encoding ascii
    Write-Host "Owner-signed artifacts staged at $dest. Device tests and publication remain separate."
} finally {
    if ($entered) { Pop-Location }
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
    }
    $store.Dispose()
    $secret.Dispose()
}
