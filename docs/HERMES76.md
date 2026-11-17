# HBC 76 preview

Framework Binary Inspector now recognizes the HBC 76 no-CJS classic header,
16-byte non-overflow small function headers, bounded string tables and
linear opcode/operand previews. Global function plus up to 63 other headers;
up to eight functions and 128 instructions each. Register pseudocode for
selected move/constant/arithmetic/return instructions only. Unknown versions,
overflow function headers and CJS layouts are not guessed. Switch/branch target
validation, exception/debug information, dataflow and original JS remain pending.
Footer is excluded, not cryptographically validated. Synthetic fixtures only.
Opcode data derived from hbctool v0.1.5, MIT license retained at
third_party/licenses/hbctool-MIT.txt.
https://github.com/bongtrop/hbctool/tree/v0.1.5/hbctool/hbc/hbc76
