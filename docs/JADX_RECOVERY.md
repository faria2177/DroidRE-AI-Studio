# Advanced source recovery (Windows)

Install Java compatible with the trusted official JADX release. Download the
cross-platform distribution from https://github.com/skylot/jadx/releases and
extract it; select java.exe and the distribution's lib/jadx-*-all.jar.
Tools → JADX Java Source Recovery → select destination → trust confirmation
→ Decompile Java sources. The external CLI receives separate arguments;
no shell, APK execution or automatic download. Two threads, 1536 MiB Java
heap, 15-minute wait ceiling, bounded log and output inventory (20,000
filesystem entries). Output remains in a unique session folder; the source
APK hash is checked before use. Nonzero exit with files is explicitly partial.
RECOVERY_REPORT.json records the result. Actual Java/resource compilation
is not guaranteed. Disk usage is not capped by the bridge; ensure space.
Use isolated VM for untrusted inputs. No external tools bundled.

On Android and Windows, the Framework Recovery Index lists observed DEX,
Flutter AOT/assets, React Native bundle, Unity native/managed/metadata and
NativeScript path hints, up to 250 per group. It does not reconstruct
original Flutter, React Native, Unity or NativeScript projects.
Current built-in source preview ZIP remains unchanged. External JADX
integration requires real local tool testing; unit tests cover invocation
arguments, bounded output counting and framework classification.
