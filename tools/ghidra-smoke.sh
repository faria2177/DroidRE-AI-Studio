#!/usr/bin/env bash
set -euo pipefail
root="$(realpath "$1")"
session="$2"
mkdir -p "$session"
session="$(realpath "$session")"
scriptdir="$(realpath assets/ghidra)"
cat > "$session/fixture.c" <<'EOF'
__attribute__((noinline)) int adjust(int value) {
    if (value > 3) return value + 2;
    return value - 1;
}
int main(int argc, char **argv) {
    (void)argv;
    return adjust(argc);
}
EOF
gcc -g -O0 -fno-inline -o "$session/sample.elf" "$session/fixture.c"
# Exercise the same direct Java entry point and fixed analysis limits as the app.
env -u JAVA_TOOL_OPTIONS -u _JAVA_OPTIONS -u JDK_JAVA_OPTIONS DEBUGINFOD_URLS='' \
    timeout 300 java -Xmx1536m -XX:ActiveProcessorCount=2 -Djava.awt.headless=true \
    -Djava.system.class.loader=ghidra.GhidraClassLoader -Dfile.encoding=UTF-8 \
    -Duser.language=en -Duser.country=US \
    -cp "$root/Ghidra/Framework/Utility/lib/Utility.jar" ghidra.GhidraLauncher \
    ghidra.app.util.headless.AnalyzeHeadless "$session" DroidRE \
    -import "$session/sample.elf" -readOnly -deleteProject -max-cpu 2 \
    -analysisTimeoutPerFile 90 -scriptPath "$scriptdir" -postScript \
    DroidREHeadlessExport.java "$session/native-evidence.tsv" adjust \
    2>&1 | tee "$session/launcher.log"
python3 - "$session/native-evidence.tsv" <<'PY'
import base64, pathlib, sys
rows = [s.split('\t') for s in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert rows[0][0] == 'DROIDRE1' and rows[-1][0] == 'END'
functions = [r for r in rows if r[0] == 'F']
previews = [r for r in rows if r[0] == 'P']
assert len(functions) == int(rows[-1][1]) and len(previews) == int(rows[-1][2])
target = next(r[1] for r in functions if base64.b64decode(r[2]).decode() == 'adjust')
assert any(r[1] == target and r[2] == 'observed' and 'adjust' in base64.b64decode(r[3]).decode()
           for r in previews)
assert any(r[0] == 'B' and r[1] == target for r in rows)
assert any(r[0] == 'E' and r[1] == target for r in rows)
print('Synthetic Ghidra function and CFG evidence verified.')
PY
