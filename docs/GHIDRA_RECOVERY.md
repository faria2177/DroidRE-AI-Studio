# Phase 24 — optional Ghidra workflow

Install trusted Ghidra separately and import an authorized ELF/PE in Ghidra.
Run its normal analysis. Add tools/ghidra to Script Manager's script directories,
select a function in CodeBrowser and run DroidREExportFunction.java. Save a new
.txt file. Open its containing folder in DroidRE Universal Project Workspace.
The script exports bounded selected-function C-like pseudocode, entry point,
language and up to 128 statically observed calls; 30 second decompiler timeout.
Original executable is not modified or run. This is a manual integration, not
an embedded Ghidra engine, full CFG or compiler. Real Ghidra compile/run validation
is pending; use trusted tools and authorized input or an isolated VM.
API: https://ghidra.re/ghidra_docs/api/ghidra/app/decompiler/DecompInterface.html
