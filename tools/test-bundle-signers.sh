#!/usr/bin/env bash
# Disposable synthetic fixtures only. No production key or application code.
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
mkdir -p base/manifest
printf 'demo' > BundleConfig.pb
printf 'demo' > base/manifest/AndroidManifest.xml
jar --create --file signed.aab BundleConfig.pb base/manifest/AndroidManifest.xml
keytool -genkeypair -alias test -keyalg RSA -keysize 2048 -validity 2 \
    -dname 'CN=Disposable test key' -keystore test.p12 \
    -storepass disposable -keypass disposable >/dev/null 2>&1
jarsigner -keystore test.p12 -storepass disposable signed.aab test >/dev/null
hash="$(keytool -exportcert -alias test -keystore test.p12 -storepass disposable | sha256sum | cut -d' ' -f1)"
java "$source_dir/VerifyBundleSigners.java" signed.aab "$hash"
cp signed.aab unsigned-extra.aab
printf 'unsigned' > extra.txt
zip -q unsigned-extra.aab extra.txt
if java "$source_dir/VerifyBundleSigners.java" unsigned-extra.aab "$hash" > rejected.log 2>&1; then
    echo 'ERROR: unsigned payload accepted' >&2
    exit 1
fi
grep -q 'Missing or multiple signers' rejected.log
if java "$source_dir/VerifyBundleSigners.java" signed.aab "$(printf '0%.0s' {1..64})" > mismatch.log 2>&1; then
    echo 'ERROR: wrong certificate accepted' >&2
    exit 1
fi
grep -q 'Unexpected leaf certificate' mismatch.log
echo 'Bundle signer fixture checks passed.'
