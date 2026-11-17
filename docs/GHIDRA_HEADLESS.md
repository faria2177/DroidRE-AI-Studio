# Integrated Ghidra headless preview (Windows)

Tools → Ghidra Native Decompiler, or APK ELF disassembly → Ghidra decompiler.
Select a trusted compatible JDK java.exe, extracted Ghidra installation and output
parent. Standalone ELF/MZ or an APK .so member up to 32 MiB is copied into a
fresh session; original never modified. No execution of target code.
Direct Java launch via Utility.jar and ghidra.GhidraLauncher is version-dependent
and may require additional JVM options. 1536 MiB heap, two CPU cores, 90-second
analysis timeout and five-minute process wait. No bundled Ghidra.
Script exports up to 256 functions, 24 static calls each, and C-like pseudocode
for first 12 functions or exact address/name within sampled inventory (8-second
decompile timeout each, 12,000 characters each). Not a complete CFG/runtime graph.
Report must contain a final completion marker. Session includes input copy, script,
report and hash. Review and remove when no longer needed. Disk and child processes
are not sandboxed; timeout kills JVM, not necessarily descendants. Use trusted tools
and authorized samples, preferably in isolated VM. Unit tests exercise Dart parser
and args. Actual Ghidra/JDK runtime and Java script compile validation pending.
Reference: https://ghidra.re/ghidra_docs/GhidraClass/Intermediate/HeadlessAnalyzer.html

Phase 34: BasicBlockModel exports up to 32 block starts per decompiled function and examines up to 8 destination references per block, skipping calls and external targets. View observed block edges and copy Graphviz DOT of sampled internal edges. Not a complete CFG or graphical in-app renderer. Ghidra Java compile/run testing pending.
