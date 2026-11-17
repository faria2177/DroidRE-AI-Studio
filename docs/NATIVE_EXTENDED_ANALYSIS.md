# Extended native analysis

Open ELF Explorer → executable section or sized function → Native analysis / LLVM.
The built-in ARM64 preview keeps the existing linear sweep. Incoming direct
branch search scans at most the first 16,384 words of the chosen section and
returns at most 256 matches for an aligned hexadecimal virtual address. It
includes BL calls, conditional and unconditional branches, not indirect calls.
Unknown words and scan limits mark partial coverage. Data may resemble code.

Windows: select a trusted llvm-objdump.exe from an Android NDK installation
(e.g. NDK/toolchains/llvm/prebuilt/windows-x86_64/bin). The bridge runs the
external tool without a shell on a temporary ELF copy; ARM/Thumb, AArch64,
x86 and x86-64 decoding depends on the tool and ELF metadata. Preview begins
at the selected section or valid sized function and covers at most 4 KiB,
with 128 Ki characters of output and a 45-second timeout. ARM Thumb function
symbol bit zero is cleared for range selection; LLVM determines decoding mode.
No forced disassembly of data, native execution, full call graph, code recovery
or cross-library relocation resolution. External LLVM is not bundled or
sandboxed; only use trusted tools and inputs, or an isolated VM. Unit tests
exercise argument generation and built-in branch search; real LLVM integration
is not yet validated.
