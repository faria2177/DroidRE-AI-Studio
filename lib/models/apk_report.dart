class ApkEntry {
  const ApkEntry({required this.name, required this.size, required this.isFile});

  final String name;
  final int size;
  final bool isFile;

  Map<String, Object?> toJson() => {
    'name': name,
    'size': size,
    'isFile': isFile,
  };

  factory ApkEntry.fromJson(Map<String, dynamic> json) => ApkEntry(
    name: json['name'] as String? ?? '',
    size: json['size'] as int? ?? 0,
    isFile: json['isFile'] as bool? ?? true,
  );
}

class ManifestInfo {
  const ManifestInfo({
    this.packageName = '',
    this.versionName = '',
    this.versionCode = '',
    this.minSdk = '',
    this.targetSdk = '',
    this.permissions = const [],
    this.activities = const [],
    this.services = const [],
    this.receivers = const [],
    this.providers = const [],
    this.decoded = false,
  });

  final String packageName;
  final String versionName;
  final String versionCode;
  final String minSdk;
  final String targetSdk;
  final List<String> permissions;
  final List<String> activities;
  final List<String> services;
  final List<String> receivers;
  final List<String> providers;
  final bool decoded;

  Map<String, Object?> toJson() => {
    'packageName': packageName,
    'versionName': versionName,
    'versionCode': versionCode,
    'minSdk': minSdk,
    'targetSdk': targetSdk,
    'permissions': permissions,
    'activities': activities,
    'services': services,
    'receivers': receivers,
    'providers': providers,
    'decoded': decoded,
  };

  factory ManifestInfo.fromJson(Map<String, dynamic> json) => ManifestInfo(
    packageName: json['packageName'] as String? ?? '',
    versionName: json['versionName'] as String? ?? '',
    versionCode: json['versionCode'] as String? ?? '',
    minSdk: json['minSdk'] as String? ?? '',
    targetSdk: json['targetSdk'] as String? ?? '',
    permissions: _strings(json['permissions']),
    activities: _strings(json['activities']),
    services: _strings(json['services']),
    receivers: _strings(json['receivers']),
    providers: _strings(json['providers']),
    decoded: json['decoded'] as bool? ?? false,
  );
}

List<String> _strings(Object? value) =>
    value is List ? value.map((item) => item.toString()).toList() : [];

class ApkReport {
  const ApkReport({
    required this.id,
    required this.fileName,
    required this.localPath,
    required this.size,
    required this.sha256,
    required this.importedAt,
    required this.entries,
    required this.entryCount,
    required this.dexFiles,
    required this.nativeLibraries,
    required this.manifest,
    required this.framework,
    required this.warnings,
  });

  final String id;
  final String fileName;
  final String localPath;
  final int size;
  final String sha256;
  final DateTime importedAt;
  final List<ApkEntry> entries;
  final int entryCount;
  final List<String> dexFiles;
  final List<String> nativeLibraries;
  final ManifestInfo manifest;
  final String framework;
  final List<String> warnings;

  int get dexCount => dexFiles.length;
  int get nativeCount => nativeLibraries.length;
  String get packageLabel =>
      manifest.packageName.isEmpty ? fileName : manifest.packageName;

  Map<String, Object?> toJson() => {
    'id': id,
    'fileName': fileName,
    'localPath': localPath,
    'size': size,
    'sha256': sha256,
    'importedAt': importedAt.toIso8601String(),
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'entryCount': entryCount,
    'dexFiles': dexFiles,
    'nativeLibraries': nativeLibraries,
    'manifest': manifest.toJson(),
    'framework': framework,
    'warnings': warnings,
  };

  factory ApkReport.fromJson(Map<String, dynamic> json) => ApkReport(
    id: json['id'] as String? ?? '',
    fileName: json['fileName'] as String? ?? '',
    localPath: json['localPath'] as String? ?? '',
    size: json['size'] as int? ?? 0,
    sha256: json['sha256'] as String? ?? '',
    importedAt:
        DateTime.tryParse(json['importedAt'] as String? ?? '') ?? DateTime(2000),
    entries: (json['entries'] as List? ?? [])
        .whereType<Map>()
        .map((entry) => ApkEntry.fromJson(Map<String, dynamic>.from(entry)))
        .toList(),
    entryCount: json['entryCount'] as int? ?? 0,
    dexFiles: _strings(json['dexFiles']),
    nativeLibraries: _strings(json['nativeLibraries']),
    manifest: ManifestInfo.fromJson(
      Map<String, dynamic>.from(json['manifest'] as Map? ?? {}),
    ),
    framework: json['framework'] as String? ?? 'Unknown',
    warnings: _strings(json['warnings']),
  );
}
