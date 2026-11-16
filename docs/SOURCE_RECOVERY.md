# On-device Android source recovery

DroidRE AI Studio can inspect an imported APK locally, then create a
**visible project folder in a location the user chooses through Android
File Manager**, outside the app's private \`Android/data\` directory.

## First import: choose a public destination

1. Tap **Import APK** and choose a local APK.
2. When the APK has been indexed, Android opens its system **Select folder**
   picker (unless a previously authorized destination is available).
3. Choose an existing writable folder, such as \`Documents\` or a custom
   \`Documents/DroidRE\` folder, and confirm the access request.
4. The app creates \`DroidRE_<package>_<project-id>/\` inside the selected
   folder. It never overwrites an existing project folder.
5. Open **Tools → Browse Generated Code** to inspect files. You can also
   open the selected location with the phone's usual File Manager, or
   **Export Source Preview ZIP** to copy the results.

The chosen destination is remembered using a persisted Android Storage
Access Framework (SAF) folder grant. Use **Tools → Choose File Manager Folder**
to change it. You can use **Generate Code in Selected Folder** for an
already-imported APK if the first import was cancelled or its destination
became unavailable.

**Android 11+ limitations:** The system folder selector does not allow
the storage-volume root, Downloads root, or protected \`Android/data\` /
\`Android/obb\` trees. Not every arbitrary folder or cloud provider is
writable. Choose a supported subfolder that the system allows. No
\`MANAGE_EXTERNAL_STORAGE\` or broad device-wide permission is requested.

If folder selection is cancelled, APK import succeeds but public-folder
generation is skipped until the user chooses a destination. Failed writes
are reported and cleanup is attempted. Source files are not automatically
sent to an AI provider or server.

## Generated structure

\`\`\`text
Documents/
  DroidRE_com.example.app_<project-id>/
    README.md
    REPORT.json
    framework/
      TECHNOLOGY_ANALYSIS.md
    source/
      java_like/dex_01/com/example/Main_0001.java.txt
      dalvik/dex_01/com/example/Main_0001.dalvik.txt
    recovered/
      dex_01/
        INDEX.txt
        CLASS_METADATA.json
        ANNOTATIONS_INDEX.json
        classes/0001/class.txt
        classes/0001/methods.txt
        classes/0001/method_semantics.json
        classes/0001/annotations.json (if present)
        classes/0001/java_like.txt
        classes/0001/dalvik.txt
    resources/
      raw/0001.bin
      decoded/0001.xml
\`\`\`

The file names are illustrative. Files vary with APK contents and bounded
analysis results. Each DEX also includes `CLASS_METADATA.json` with
class descriptors, access flags, superclass, implemented interfaces,
source-file hints, and static/instance field declarations.
`class.txt` and `source/dalvik/` now carry a Smali-like structural
preview (`.class`, `.super`, `.implements`, `.field`). These are
inspection reports, **NOT verified or assemblable Smali**.

The new `method_semantics.json` records bounded instruction-offset-aware
references (string/type/field/method/polymorphic prototype, with unresolved
dynamic IDs explicitly labeled) and DEX `code_item` try/catch ranges,
typed handlers and catch-all handler addresses in 16-bit code units.
`ANNOTATIONS_INDEX.json` records class, field, method and parameter
annotation **type descriptors, visibility and encoded element counts**;
it does not decode annotation values or reproduce assembly-ready directives.
Malformed metadata is reported as partial, independently of other method
decoding. `REPORT.json` includes source APK SHA-256, detected
framework, decoded DEX/class/method counts, resource inventory,
partial-results flag and warnings.

## Technology-aware code analysis

- **Native Android / unknown framework:** DEX method inventory, Dalvik
  instruction inspection and Java-like pseudocode. This is *not* verified
  Smali and *not* original Java or Kotlin source.
- **Flutter:** Android host DEX code, available resource previews and
  native library inventory. Flutter Dart AOT code in \`.so\` files is
  *not* reconstructed into original Dart source.
- **React Native:** Android bridge DEX inspection and bounded assets;
  original TypeScript/JavaScript source maps are not recovered.
- **Unity:** Android wrapper and native libraries are inventoried.
  Original Unity C# and IL2CPP source are not recovered.
- **NativeScript:** Android-side DEX plus bounded assets; original
  TypeScript/JavaScript project source is not guaranteed.

Technology detection is heuristic. \`framework/TECHNOLOGY_ANALYSIS.md\`
contains the detection result and the specific limitations for each app.
Split APK containers (APKS/APKM/XAPK) and AAB packages are not fully
reconstructed by this milestone; their nested DEX and resource content
may not be decoded.

## Scope, safety and limits

- First 3 supported DEX files, 80 classes and 400 methods.
- Up to 512 field declarations and 128 interfaces per class. Truncation
  is reported instead of silently discarding additional declarations.
- At most 32 small resources (256 KiB each, 4 MiB combined).
- Per method: 128 try regions, 256 handler groups, 64 typed catches per
  handler, 160 indexed references and a 50,000-instruction inspection cap.
- Per annotation directory: up to 64 owners per kind, 32 annotation types
  per set and 32 parameter positions per method. Partial flags mark limits.
- Source ZIP at most 24 MiB; SAF writer enforces a 48 MiB expanded
  data cap and 900-file cap.
- Invalid class/field/exception/annotation metadata is reported while
  independently decodable methods remain exportable. Field ID ownership is checked.
- Large or unsupported methods/resources are skipped with diagnostics;
  incomplete analysis is not silently called complete.
- All generated Java-like and Dalvik files use a final \`.txt\` extension,
  because the output **cannot be compiled or reassembled**.
- Original APK remains unchanged. ZIP path traversal, duplicates and
  output overwrites are rejected.
- SAF authorization is limited to the user-selected tree. Existing
  generated folders are retained when the destination changes.
- Generated source can contain private strings, code or keys. Review it
  before sharing. Inspect apps you own or are authorized to analyze.

## Validation status

The source code and regression tests are committed, but **no new APK
build or CI run was requested**. Android 11–16 device validation is still
required, especially for folder picker grants, document-provider
performance, cancellation, storage quotas and File Manager access.

See \`test/source_recovery_framework_test.dart\`,
\`test/saf_source_recovery_service_test.dart\` and
\`test/dex_class_metadata_inspector_test.dart\`,
\`test/dex_method_semantics_inspector_test.dart\`, and
\`test/dex_class_annotation_inspector_test.dart\` for regression tests.
Future work includes more faithful Smali, deeper DEX/ELF decompilation,
full resource recovery and a verified buildable project scaffold.
