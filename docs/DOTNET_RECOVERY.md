# .NET assembly evidence and recovery

Universal Binary Inspector → open managed PE DLL/EXE → directoryAnalysis.clr.
The local parser inventories ECMA-335 metadata streams (32 max), validates
stream boundaries and reads declared table row counts from #~ or #-.
No table rows, heap contents, method IL or strong-name validation is inferred.

Windows: install an official compatible .NET SDK and ILSpy CLI:
`dotnet tool install --global ilspycmd` (see current ILSpy requirements).
Select the trusted local ilspycmd.exe (typically %USERPROFILE%\.dotnet\tools).
For detected CLR metadata choose .NET IL & C# Recovery. Select one of
IL preview, C# preview, managed type list or C# project export. CLI update
check disabled; no shell or execution of input assembly. SHA-256 checked,
32 MiB input limit, five-minute wait, 128 Ki characters per output stream.
A new destination subfolder is used for projects. Disk output is not capped,
and no compile or runtime validation is performed. Nonzero exit or clipped
output is marked partial. External CLI is not sandboxed; use trusted tools
and authorized inputs or an isolated VM. No automatic installation or upload.

Tests exercise metadata stream ranges/counts and CLI argument construction.
Real ILSpy round-trip and device validation pending.
Reference: https://github.com/icsharpcode/ILSpy/tree/master/ICSharpCode.ILSpyCmd
