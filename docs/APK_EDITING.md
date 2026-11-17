# Authorized APK asset editor and Windows signing

Tools → APK Asset Editor → choose existing UTF-8 asset → Load → edit →
Repack and export unsigned APK. Only edit APKs you own or have permission
to modify. Limits: 48 MiB input, 64 MiB expanded/output, 512 KiB asset,
10,000 entries and 200 visible candidates. JSON syntax is checked.
Reopened ZIP file payloads are SHA-256 verified. Original imported copy is
not modified. Old JAR signature files and APK signing block are not copied.
ZIP ordering, compression, directories, timestamps and alignment can change.
No compiled resource, manifest, DEX or native editing is implemented.

## Windows

Install Java, Android SDK Build Tools 35+ (zipalign -P 16), and use your
authorized signing keystore. Example from repository root in PowerShell:

    .\tools\sign-edited-apk.ps1 -UnsignedApk C:\work\edited-unsigned.apk -OutputApk C:\work\edited-signed.apk -BuildToolsDir C:\Android\Sdk\build-tools\35.0.0 -Keystore C:\keys\owner.jks -Alias owner

Use actual paths. apksigner prompts for passwords; do not commit secrets.
The script aligns, signs, verifies signatures and alignment, then copies
a new file without overwriting. It outputs SHA-256. Installation is not
guaranteed even after signing; different signing keys cannot update an
existing installation signed by the original key. On-device signing and
full rebuild are not implemented. Windows helper requires target SDK
validation.
