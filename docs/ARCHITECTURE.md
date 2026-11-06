# Architecture

## MVP components

```mermaid
flowchart TD
  UI[Flutter Material 3 UI] --> STORE[Local project controller]
  STORE --> FILES[User-picked local APK copies]
  FILES --> ZIP[Streaming ZIP inventory]
  ZIP --> XML[Binary XML manifest parser]
  ZIP --> DEX[Bounded DEX class/method index reader]
  ZIP --> ELF[Bounded ELF header reader]
  ZIP --> RES[Resource/asset preview and resource table headers]
  UI --> CHAT[Explicit text-only AI adapter]
  CHAT --> API[Selected authorized provider]
```

- `lib/main.dart`: Material 3 app and themes.
- `lib/screens/studio_screens.dart`: working project and inspector screens.
- `lib/services/studio_controller.dart`: import, project index and persistence.
- `lib/services/apk_analyzer.dart`: ZIP metadata, SHA-256, DEX/native inventory.
- `lib/services/android_manifest_parser.dart`: bounded Android binary XML parser.
- `lib/services/package_binary_reader.dart`: user-selected, bounded binary member extraction.
- `lib/services/dex_inspector.dart`: DEX 035–040 header/class/method/prototype reader, on-demand instruction decoder.
- `lib/services/dalvik_disassembler.dart`: bounded Dalvik opcode/operand decoder with explicit rejection of unknown formats.
- `lib/services/dex_symbol_index.dart`: bounded DEX string/type/proto/method/field reference decoding, reused by disassembly and indexed cross-reference navigation.
- `lib/services/dex_call_graph.dart`: bounded per-APK Multi-DEX signature-matched static invocation edges and two-hop call graph UI.
- `lib/services/dalvik_pseudocode.dart`: conservative Java-like pseudocode renderer with original Dalvik offsets.
- `lib/services/elf_inspector.dart`: ELF32/ELF64 metadata reader.
- `lib/services/resource_inspector.dart`: `resources.arsc` package metadata and bounded asset previews.
- `lib/services/android_binary_xml_decoder.dart`: bounded Android binary XML element/attribute hierarchy viewer.
- `lib/screens/binary_explorer_tabs.dart`: on-demand inspectors with class search.
- `lib/screens/resource_explorer_tab.dart`: path/category search and resource detail viewer.
- `lib/services/ai_chat_service.dart`: opt-in chat calls; no automatic binary context.
- `lib/services/google_account_service.dart`: OAuth account chooser when configured.

## Future engine split

- Flutter UI and task coordination remain in Dart.
- A Kotlin/Java plugin may later provide full Smali and native ELF disassembly.
- Heavy JADX/Apktool/Ghidra operations need Android compatibility validation or
  a separately approved external worker.
- Project source APKs remain local unless user explicitly authorizes export.

## Trust boundary

Imported files are untrusted. The MVP lists archive entries but does not
extract arbitrary paths or execute embedded bytecode. Manifest parsing has
size and count limits. AI keys remain only in memory during the session.
Never add automatic uploading of whole packages or credentials.
