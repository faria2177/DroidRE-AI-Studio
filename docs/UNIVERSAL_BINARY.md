# Universal Binary Inspector

Tools → Universal Binary Inspector → Open binary file. Works independently
of APK project selection. Local 32 MiB limit; SHA-256, PE32/PE32+ headers,
machine, DLL flag, entry RVA, image base, section ranges/permissions and
declared directory address fields. ELF uses the existing header inspector.
Malformed signatures remain candidate labels, not validated executables.
No import/export table parsing, Authenticode verification or execution.
PE reference: https://learn.microsoft.com/en-us/windows/win32/debug/pe-format

Hex/ASCII pages of 256 bytes, arbitrary hexadecimal file offset, exact
hex or UTF-8 byte search (1–256 bytes, first 1,000 matches, overlaps included).
Windows: explicit copy-only hex replacement up to 256 bytes; existing file
length unchanged. Choose a new output filename, original loaded data remains
unchanged. No automatic checksum/signature repair, install or runtime guarantee.
Only use authorized files. Synthetic unit tests cover ranges, search and copies;
actual platform file-picker validation pending.
