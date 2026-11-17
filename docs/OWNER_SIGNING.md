# Owner-controlled Android signing (Windows)

The ordinary CI artifacts remain debug-signed. No production key is bundled.
For a deliberate owner release, Gradle reads five environment variables:
DROIDRE_PRODUCTION_SIGNING=1, DROIDRE_KEYSTORE (absolute owner keystore),
DROIDRE_KEY_ALIAS, DROIDRE_STORE_PASSWORD, DROIDRE_KEY_PASSWORD.
Missing values or a known debug key name/alias fail configuration. A normal
test build without the explicit flag retains the debug signing configuration.

On Windows with Flutter, JDK 17 (keytool/jarsigner on PATH), and Android SDK
Build Tools, use the local PowerShell helper:
    
    .\tools\build-owner-release.ps1 -Keystore "D:\secure\owner.jks" -Alias "release" -BuildToolsDir "C:\Android\Sdk\build-tools\36.0.0" -ExpectedCertSha256 "<64 hex digits>" -OutputParent "D:\releases"

Use your own known signing certificate SHA-256 (without colons), independently
obtained from your keystore with keytool -list -v. The helper prompts privately
for passwords, passes them through temporary process environment, runs analyze
and tests, builds split APKs and an AAB, checks APK signatures and expected
fingerprints, checks the bundle JAR signature and expected certificate, then
copies artifacts and SHA-256 checksums into a fresh output directory. It does
not publish or store passwords in a file. Gradle/Java child processes receive
the signing environment; only run on a trusted machine. Clear/stop Gradle
daemons after signing and restrict local access.

The AAB check is not full Play Store acceptance or certificate trust
validation. Owner key backup, real signed-build verification and installation
tests are required before production distribution. Never commit or send the
keystore/password. Windows Authenticode signing remains separate.

The bundle verifier reads each non-signature JAR payload, requires exactly one
signer with the expected leaf certificate, rejects unsigned additions, mismatches
and duplicate entry names, and requires the basic bundle members. Synthetic signed,
unsigned-addition and wrong-certificate fixtures are exercised by the CI test.
This verifies signed payloads, not Android bundle semantic validity or trust.
