import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/apk_report.dart';
import '../services/local_export_service.dart';
import '../services/ai_chat_service.dart';
import '../services/google_account_service.dart';
import '../services/studio_controller.dart';
import '../services/source_recovery_bundle.dart';
import 'binary_explorer_tabs.dart';
import 'resource_explorer_tab.dart';
import 'recovered_folder_browser.dart';
import 'apk_asset_editor_screen.dart';
import 'apk_security_screen.dart';
import 'apktool_workspace_screen.dart';
import 'jadx_recovery_screen.dart';
import 'project_context_dialog.dart';
import 'semantic_context_dialog.dart';
import 'analysis_agent_screen.dart';
import 'adb_device_screen.dart';
import 'framework_binary_screen.dart';
import 'universal_binary_screen.dart';
import 'project_workspace_screen.dart';
import 'archive_member_export_screen.dart';
import 'paged_binary_screen.dart';
import 'ghidra_headless_screen.dart';
import 'split_set_screen.dart';
import 'external_tool_manager_screen.dart';
import 'package:file_picker/file_picker.dart';
import '../services/framework_recovery_index.dart';
import 'dart:convert';

class StudioShell extends StatefulWidget {
  const StudioShell({super.key, required this.controller});

  final StudioController controller;

  @override
  State<StudioShell> createState() => _StudioShellState();
}

class _StudioShellState extends State<StudioShell> {
  int _tab = 0;
  String _aiDraft = '';

  void _analyzeSelectedCode(String draft) {
    setState(() {
      _aiDraft = draft;
      _tab = 3;
    });
  }

  static const _titles = [
    'Home',
    'Projects',
    'APK Inspector',
    'AI Studio',
    'Tools',
  ];
  static const _icons = [
    Icons.dashboard_outlined,
    Icons.folder_copy_outlined,
    Icons.code_outlined,
    Icons.auto_awesome_outlined,
    Icons.handyman_outlined,
  ];
  static const _selectedIcons = [
    Icons.dashboard,
    Icons.folder_copy,
    Icons.code,
    Icons.auto_awesome,
    Icons.handyman,
  ];

  Future<void> _import() async {
    final completed = await widget.controller.importApk();
    if (mounted && completed) setState(() => _tab = 2);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final width = MediaQuery.sizeOf(context).width;
        final wide = width >= 850;
        final expandedRail = width >= 1150;
        final tabs = <Widget>[
          HomeScreen(
            controller: widget.controller,
            onImport: _import,
            openProjects: () => setState(() => _tab = 1),
            openInspector: () => setState(() => _tab = 2),
          ),
          ProjectsScreen(
            controller: widget.controller,
            onImport: _import,
            onOpen: () => setState(() => _tab = 2),
          ),
          InspectorScreen(
            report: widget.controller.active,
            onExplainCode: _analyzeSelectedCode,
          ),
          AiStudioScreen(
            key: ValueKey(_aiDraft),
            initialPrompt: _aiDraft,
            report: widget.controller.active,
          ),
          ToolsScreen(
            controller: widget.controller,
            report: widget.controller.active,
            onImport: _import,
            onAnalyze: () => setState(() => _tab = 2),
          ),
        ];
        return Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.keyO, control: true): _ImportApkIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _ImportApkIntent: CallbackAction<_ImportApkIntent>(onInvoke: (_) {
                if (!widget.controller.busy) {
                  _import();
                }
                return null;
              }),
            },
            child: Focus(autofocus: true, child: Scaffold(
          appBar: AppBar(
            titleSpacing: 20,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/branding/droidre_logo.png',
                  width: 32,
                  height: 32,
                  semanticLabel: 'DroidRE AI Studio logo',
                ),
                const SizedBox(width: 10),
                Text(wide ? 'DroidRE AI Studio' : _titles[_tab]),
              ],
            ),
            actions: [
              if (widget.controller.busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              IconButton(
                tooltip: 'Import APK',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: widget.controller.busy ? null : _import,
              ),
              IconButton(
                tooltip: 'Account and settings',
                icon: const Icon(Icons.account_circle_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AccountSettingsScreen(),
                  ),
                ),
              ),
            ],
          ),
          body: Row(
            children: [
              if (wide)
                NavigationRail(
                  selectedIndex: _tab,
                  onDestinationSelected: (value) => setState(() => _tab = value),
                  extended: expandedRail,
                  minExtendedWidth: 208,
                  labelType: expandedRail ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                  destinations: List.generate(
                    _titles.length,
                    (index) => NavigationRailDestination(
                      icon: Icon(_icons[index]),
                      selectedIcon: Icon(_selectedIcons[index]),
                      label: Text(_titles[index]),
                    ),
                  ),
                ),
              if (wide) const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    if (wide && widget.controller.active != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: Text('Active project: ${widget.controller.active!.fileName}',
                            overflow: TextOverflow.ellipsis),
                      ),
                    if (widget.controller.error != null)
                      MaterialBanner(
                        content: Text(widget.controller.error!),
                        actions: [
                          TextButton(
                            onPressed: widget.controller.clearError,
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    if (widget.controller.recoveryMessage != null)
                      MaterialBanner(
                        content: Text(widget.controller.recoveryMessage!),
                        actions: [
                          TextButton(
                            onPressed: () => setState(() => _tab = 4),
                            child: const Text('View generated files'),
                          ),
                          TextButton(
                            onPressed: widget.controller.clearRecoveryMessage,
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    Expanded(child: tabs[_tab]),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _tab,
                  height: 76,
                  onDestinationSelected: (value) => setState(() => _tab = value),
                  destinations: List.generate(
                    _titles.length,
                    (index) => NavigationDestination(
                      icon: Icon(_icons[index]),
                      selectedIcon: Icon(_selectedIcons[index]),
                      label: _titles[index] == 'APK Inspector'
                          ? 'Analyze'
                          : _titles[index],
                    ),
                  ),
                ),
        ))));
      },
    );
  }
}

class _ImportApkIntent extends Intent {
  const _ImportApkIntent();
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.onImport,
    required this.openProjects,
    required this.openInspector,
  });

  final StudioController controller;
  final VoidCallback onImport;
  final VoidCallback openProjects;
  final VoidCallback openInspector;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final latest = controller.active;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xff174d55), Color(0xff1b3050)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(
                'assets/branding/droidre_logo.png',
                width: 76,
                height: 76,
                semanticLabel: 'DroidRE AI Studio logo',
              ),
              const SizedBox(height: 14),
              const Text(
                'Explore the inside of Android apps',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Local APK inspection, manifest details, DEX inventory, '
                'native libraries and opt-in AI explanations.',
                style: TextStyle(color: Color(0xffd1e5e9), height: 1.4),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: controller.busy ? null : onImport,
                icon: const Icon(Icons.file_open),
                label: const Text('Import an APK or bundle'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text('Workspace', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            MetricCard(value: '${controller.projects.length}', label: 'Projects', icon: Icons.folder),
            MetricCard(value: '${latest?.dexCount ?? 0}', label: 'DEX files', icon: Icons.data_object),
            MetricCard(value: '${latest?.nativeCount ?? 0}', label: 'Native libs', icon: Icons.memory),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent project', style: Theme.of(context).textTheme.titleLarge),
            TextButton(onPressed: openProjects, child: const Text('See all')),
          ],
        ),
        if (latest == null)
          const EmptyPanel(
            icon: Icons.inventory_2_outlined,
            title: 'No projects yet',
            description: 'Import your first APK to inspect real package data.',
          )
        else
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                backgroundColor: color.primary.withValues(alpha: 0.12),
                child: const Icon(Icons.android),
              ),
              title: Text(latest.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(latest.packageLabel, maxLines: 1),
              trailing: const Icon(Icons.chevron_right),
              onTap: openInspector,
            ),
          ),
        const SizedBox(height: 24),
        const Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            StatusPill(label: 'Offline analysis', icon: Icons.shield_outlined),
            StatusPill(label: 'Read-only by default', icon: Icons.lock_outline),
            StatusPill(label: 'AI requires consent', icon: Icons.privacy_tip_outlined),
          ],
        ),
      ],
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 17),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 50),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 7),
            Text(description, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({
    super.key,
    required this.controller,
    required this.onImport,
    required this.onOpen,
  });
  final StudioController controller;
  final VoidCallback onImport;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (controller.projects.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EmptyPanel(
              icon: Icons.folder_open,
              title: 'Your workspace is empty',
              description: 'Files are copied into app-private storage for inspection.',
            ),
            FilledButton.icon(
              onPressed: controller.busy ? null : onImport,
              icon: const Icon(Icons.add),
              label: const Text('Import APK'),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(18),
      itemCount: controller.projects.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final report = controller.projects[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.android)),
            title: Text(report.fileName),
            subtitle: Text(
              '${report.packageLabel} • ${_formatSize(report.size)} • '
              '${report.dexCount} DEX',
              maxLines: 2,
            ),
            onTap: () {
              controller.select(report);
              onOpen();
            },
            trailing: IconButton(
              tooltip: 'Remove project copy',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Remove local project?'),
                    content: const Text(
                      'This deletes only the imported app copy. '
                      'Your original source file is not affected.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) await controller.deleteProject(report);
              },
            ),
          ),
        );
      },
    );
  }
}

String _formatSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}

class InspectorScreen extends StatefulWidget {
  const InspectorScreen({super.key, required this.report,
      this.onExplainCode});
  final ApkReport? report;
  final ValueChanged<String>? onExplainCode;

  @override
  State<InspectorScreen> createState() => _InspectorScreenState();
}

class _InspectorScreenState extends State<InspectorScreen> {
  String filter = '';

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    if (report == null) {
      return const EmptyPanel(
        icon: Icons.search_off_outlined,
        title: 'Choose an APK first',
        description: 'Import a package or select a project to see analysis.',
      );
    }
    return DefaultTabController(
      key: ValueKey(report.id),
      length: 6,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 5),
                Text(
                  report.packageLabel,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Manifest'),
              Tab(text: 'Files'),
              Tab(text: 'DEX'),
              Tab(text: 'Native'),
              Tab(text: 'Resources'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _OverviewTab(report: report),
                _ManifestTab(info: report.manifest),
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          hintText: 'Search archive paths',
                        ),
                        onChanged: (text) => setState(() => filter = text),
                      ),
                    ),
                    Expanded(
                      child: Builder(builder: (context) {
                        final matches = report.entries.where(
                          (entry) => entry.name.toLowerCase().contains(filter.toLowerCase()),
                        ).toList();
                        return ListView.builder(
                          itemCount: matches.length,
                          itemBuilder: (context, index) {
                            final entry = matches[index];
                            return ListTile(
                              dense: true,
                              leading: Icon(entry.isFile
                                  ? Icons.insert_drive_file_outlined
                                  : Icons.folder_outlined),
                              title: Text(entry.name),
                              trailing: Text(_formatSize(entry.size)),
                            );
                          },
                        );
                      }),
                    ),
                  ],
                ),
                DexBrowserTab(report: report,
                    onExplainCode: widget.onExplainCode),
                ElfBrowserTab(report: report),
                ResourceExplorerTab(report: report,
                    onExplainCode: widget.onExplainCode),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.report});
  final ApkReport report;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            MetricCard(value: '${report.entryCount}', label: 'Entries', icon: Icons.list_alt),
            MetricCard(value: '${report.dexCount}', label: 'DEX', icon: Icons.data_object),
            MetricCard(value: '${report.nativeCount}', label: 'Libraries', icon: Icons.memory),
          ],
        ),
        const SizedBox(height: 12),
        _InfoTile(label: 'File size', value: _formatSize(report.size)),
        _InfoTile(label: 'Framework indicator', value: report.framework),
        _InfoTile(label: 'Package', value: report.packageLabel),
        _InfoTile(label: 'Version', value: report.manifest.versionName),
        _InfoTile(label: 'Target SDK', value: report.manifest.targetSdk),
        _InfoTile(label: 'SHA-256', value: report.sha256),
        if (report.warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Limitations and warnings', style: Theme.of(context).textTheme.titleMedium),
          for (final warning in report.warnings)
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.amber),
              title: Text(warning),
              dense: true,
            ),
        ],
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label, style: Theme.of(context).textTheme.labelMedium),
        subtitle: SelectableText(value.isEmpty ? 'Not available' : value),
      ),
    );
  }
}

class _ManifestTab extends StatelessWidget {
  const _ManifestTab({required this.info});
  final ManifestInfo info;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _InfoTile(label: 'Package', value: info.packageName),
        _InfoTile(label: 'Version code', value: info.versionCode),
        _InfoTile(label: 'Version name', value: info.versionName),
        _InfoTile(label: 'Minimum SDK', value: info.minSdk),
        _InfoTile(label: 'Target SDK', value: info.targetSdk),
        _SectionList(title: 'Permissions', names: info.permissions),
        _SectionList(title: 'Activities', names: info.activities),
        _SectionList(title: 'Services', names: info.services),
        _SectionList(title: 'Receivers', names: info.receivers),
        _SectionList(title: 'Providers', names: info.providers),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Android binary XML metadata is parsed locally. '
              'Resource references may require resources.arsc decoding.'),
        ),
      ],
    );
  }
}

class _SectionList extends StatelessWidget {
  const _SectionList({required this.title, required this.names});
  final String title;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text('$title (${names.length})'),
        children: names.isEmpty
            ? [const ListTile(title: Text('None detected'))]
            : names.map((name) => ListTile(dense: true, title: SelectableText(name))).toList(),
      ),
    );
  }
}

class AiStudioScreen extends StatefulWidget {
  const AiStudioScreen({super.key, this.initialPrompt = '', this.report});

  final String initialPrompt;
  final ApkReport? report;

  @override
  State<AiStudioScreen> createState() => _AiStudioScreenState();
}

class _AiStudioScreenState extends State<AiStudioScreen> {
  final keyController = TextEditingController();
  final modelController = TextEditingController(text: aiEndpoints.first.defaultModel);
  late final TextEditingController promptController;
  final service = AiChatService();
  final _sessionKeys = <AiEndpoint, String>{};
  final _sessionModels = <AiEndpoint, String>{};
  bool _showKey = false;
  static const _keyLinks = {
    'OpenRouter': 'https://openrouter.ai/keys',
    'OpenAI': 'https://platform.openai.com/api-keys',
    'DeepSeek': 'https://platform.deepseek.com/api_keys',
    'Groq': 'https://console.groq.com/keys',
    'Google Gemini': 'https://aistudio.google.com/apikey',
    'Anthropic Claude': 'https://console.anthropic.com/settings/keys',
    'xAI Grok': 'https://console.x.ai/',
    'Mistral': 'https://console.mistral.ai/api-keys/',
  };
  AiEndpoint endpoint = aiEndpoints.first;
  String output = '';
  bool busy = false;
  bool consentToSendCode = false;
  bool allowFallback = false;
  bool fallbackConsent = false;
  AiEndpoint? fallbackEndpoint;
  final fallbackKey = TextEditingController();
  final fallbackModel = TextEditingController();

  List<AiEndpoint> get availableEndpoints => aiEndpoints.where((item) =>
      !item.local || Platform.isWindows || Platform.isLinux || Platform.isMacOS).toList();

  @override
  void initState() {
    super.initState();
    promptController = TextEditingController(text: widget.initialPrompt);
  }

  @override
  void dispose() {
    keyController.dispose();
    modelController.dispose();
    promptController.dispose();
    fallbackKey.dispose();
    fallbackModel.dispose();
    service.close();
    super.dispose();
  }

  Future<void> _contextSearch({bool chooseFolder = false}) async {
    String? folder = widget.report?.recoveredFolderPath;
    String? uri = widget.report?.recoveredFolderUri;
    if (chooseFolder) {
      folder = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose recovered source folder');
      uri = null;
    }
    if (!mounted || (folder == null && uri == null)) {
      return;
    }
    final draft = await showDialog<String>(context: context,
      builder: (_) => ProjectContextDialog(folderPath: folder, folderUri: uri));
    if (mounted && draft != null) {
      setState(() {
        promptController.text = draft;
        consentToSendCode = false;
        fallbackConsent = false;
        output = '';
      });
    }
  }

  Future<void> _semanticSearch() async {
    final root = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose authorized recovered source folder');
    if (!mounted || root == null) {
      return;
    }
    final draft = await showDialog<String>(context: context,
      builder: (_) => SemanticContextDialog(root: root));
    if (mounted && draft != null) {
      setState(() {
        promptController.text = draft;
        consentToSendCode = false;
        fallbackConsent = false;
        output = '';
      });
    }
  }

  Future<void> _openAgent() async {
    if (busy) {
      return;
    }
    final selection = AiSelection(endpoint, modelController.text.trim(), keyController.text);
    if (selection.model.isEmpty || (!selection.endpoint.local && selection.apiKey.trim().isEmpty)) {
      setState(() => output = 'Choose a provider, model and API key (if required) before starting research.');
      return;
    }
    String? root = widget.report?.recoveredFolderPath;
    final uri = widget.report?.recoveredFolderUri;
    if (uri == null && Platform.isWindows) {
      root = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose authorized source folder for research');
    }
    if (!mounted || (root == null && uri == null)) {
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
      AnalysisAgentScreen(selection: selection, root: root, uri: uri)));
  }

  Future<void> _discover({bool fallback = false}) async {
    final selected = fallback ? fallbackEndpoint : endpoint;
    if (busy || selected == null) {
      return;
    }
    final key = fallback ? fallbackKey.text : keyController.text;
    setState(() => busy = true);
    try {
      final models = await service.listModels(selected, key);
      if (!mounted) {
        return;
      }
      if (models.isEmpty) {
        setState(() => output = 'No models listed. Enter a Model ID manually.');
        return;
      }
      final choice = await showDialog<String>(
        context: context,
        builder: (_) => _AiModelPicker(provider: selected.name, models: models),
      );
      if (mounted && choice != null) {
        setState(() {
          if (fallback) {
            fallbackModel.text = choice;
            fallbackConsent = false;
          } else {
            modelController.text = choice;
            consentToSendCode = false;
          }
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => output = 'Model discovery failed: $error. You can enter an ID manually.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _testConnection() async {
    if (busy) {
      return;
    }
    setState(() { busy = true; output = 'Testing selected provider…'; });
    try {
      final answer = await service.complete(endpoint: endpoint,
        model: modelController.text, apiKey: keyController.text,
        prompt: 'Reply with OK only.');
      if (mounted) {
        setState(() => output = 'Connection test succeeded (no project code sent).\n'
          'Provider: ${endpoint.name}\nModel: ${modelController.text}\n$answer');
      }
    } catch (e) {
      if (mounted) {
        setState(() => output = 'Connection test failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _send() async {
    if (busy || !consentToSendCode || (allowFallback && !fallbackConsent)) {
      return;
    }
    setState(() {
      busy = true;
      output = '';
    });
    try {
      final response = await service.completeWithFallback(
        primary: AiSelection(endpoint, modelController.text, keyController.text),
        fallback: fallbackEndpoint == null ? null :
          AiSelection(fallbackEndpoint!, fallbackModel.text, fallbackKey.text),
        allowFallback: allowFallback && fallbackConsent,
        prompt: promptController.text,
      );
      if (mounted) {
        setState(() => output =
            'Provider: ${response.provider}\n'
            '${response.fallbackReason == null ? '' : 'Fallback: ${response.fallbackReason}\n'}'
            '\n${response.text}');
      }
    } catch (error) {
      if (mounted) setState(() => output = 'Request failed: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('AI Code Assistant', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text('Bring your own API key. Whole APK files are never uploaded '
            'by this screen. Only the visible prompt is sent when you press Send.'),
        if (widget.report?.recoveredFolderPath != null || widget.report?.recoveredFolderUri != null)
          OutlinedButton.icon(onPressed: busy ? null : () => _contextSearch(),
            icon: const Icon(Icons.search), label: const Text('Search active recovered project')),
        if (Platform.isWindows)
          OutlinedButton.icon(onPressed: busy ? null : () => _contextSearch(chooseFolder: true),
            icon: const Icon(Icons.folder_open), label: const Text('Search JADX / local source folder')),
        if (Platform.isWindows)
          OutlinedButton.icon(onPressed: busy ? null : _semanticSearch,
            icon: const Icon(Icons.psychology_outlined), label: const Text('Local semantic code search (Ollama)')),
        const SizedBox(height: 18),
        DropdownButtonFormField<AiEndpoint>(
          initialValue: endpoint,
          decoration: const InputDecoration(
            labelText: 'AI Provider',
            border: OutlineInputBorder(),
          ),
          items: availableEndpoints.map(
            (item) => DropdownMenuItem(value: item, child: Text(item.name)),
          ).toList(),
          onChanged: busy
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() {
                    _sessionKeys[endpoint] = keyController.text;
                    _sessionModels[endpoint] = modelController.text;
                    endpoint = value;
                    keyController.text = _sessionKeys[value] ?? '';
                    modelController.text = _sessionModels[value] ?? value.defaultModel;
                    _showKey = false;
                    output = '';
                    consentToSendCode = false;
                    fallbackConsent = false;
                    if (fallbackEndpoint == value) {
                      fallbackEndpoint = null;
                      fallbackKey.clear();
                      fallbackModel.clear();
                    }
                  });
                },
        ),
        const SizedBox(height: 10),
        Text(endpoint.description),
        const SizedBox(height: 12),
        TextField(
          controller: modelController,
          enabled: !busy,
          onChanged: (_) => setState(() => consentToSendCode = false),
          decoration: const InputDecoration(
            labelText: 'Model ID',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (!endpoint.local) TextField(
          controller: keyController,
          enabled: !busy,
          obscureText: !_showKey,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() { consentToSendCode = false; fallbackConsent = false; }),
          decoration: InputDecoration(
            labelText: 'API key (session only)',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.key),
            suffixIcon: IconButton(onPressed: () => setState(() => _showKey = !_showKey),
              icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility)),
          ),
        ),
        if (_keyLinks.containsKey(endpoint.name))
          TextButton(onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _keyLinks[endpoint.name]!));
            if (mounted) {
              setState(() => output = 'API key page link copied. Open it in your browser.');
            }
          }, child: const Text('Copy official API key page link')),
        OutlinedButton.icon(onPressed: busy ? null : _testConnection,
          icon: const Icon(Icons.network_check), label: const Text('Test connection (sends OK prompt only; may use quota)')),
        const Text('If Model ID is empty, fetch available models and select one. Free plans have provider-specific limits.'),
        OutlinedButton.icon(
          onPressed: busy ? null : () => _discover(),
          icon: const Icon(Icons.manage_search),
          label: const Text('Fetch available model IDs'),
        ),
        if (Platform.isWindows || widget.report?.recoveredFolderPath != null ||
            widget.report?.recoveredFolderUri != null)
          OutlinedButton.icon(onPressed: busy ? null : _openAgent,
            icon: const Icon(Icons.account_tree_outlined), label: const Text('AI Analysis Agent (reviewed research)')),
        const SizedBox(height: 12),
        TextField(
          controller: promptController,
          enabled: !busy,
          onChanged: (_) => setState(() {
            consentToSendCode = false;
            fallbackConsent = false;
          }),
          minLines: 4,
          maxLines: 9,
          decoration: const InputDecoration(
            labelText: 'Ask about Android code',
            hintText: 'Paste the code or manifest snippet you want explained...',
            border: OutlineInputBorder(),
          ),
        ),
        CheckboxListTile(
            value: consentToSendCode,
            title: const Text('I reviewed the extracted code and agree to '
                'send this text to the selected AI provider'),
            subtitle: const Text('Check for embedded secrets first. '
                'The APK file itself stays on this device.'),
            onChanged: busy ? null : (value) => setState(() =>
                consentToSendCode = value ?? false),
          ),
        SwitchListTile(
          value: allowFallback,
          title: const Text('Enable one automatic fallback'),
          subtitle: const Text('Only on HTTP 429, 502, 503, 504 or 529. '
              'A second provider may charge separately.'),
          onChanged: busy ? null : (value) => setState(() {
            allowFallback = value;
            fallbackConsent = false;
          }),
        ),
        if (allowFallback) ...[
          DropdownButtonFormField<AiEndpoint>(
            key: ValueKey(endpoint.name),
            initialValue: fallbackEndpoint,
            decoration: const InputDecoration(
              labelText: 'Fallback provider', border: OutlineInputBorder()),
            items: availableEndpoints.where((item) => item != endpoint)
                .map((item) => DropdownMenuItem(value: item, child: Text(item.name)))
                .toList(),
            onChanged: busy ? null : (value) => setState(() {
              fallbackEndpoint = value;
              fallbackKey.clear();
              fallbackModel.text = value?.defaultModel ?? '';
              fallbackConsent = false;
            }),
          ),
          const SizedBox(height: 8),
          TextField(controller: fallbackModel, enabled: !busy,
            onChanged: (_) => setState(() => fallbackConsent = false),
            decoration: const InputDecoration(
              labelText: 'Fallback model ID', border: OutlineInputBorder())),
          if (fallbackEndpoint?.local != true) ...[
            const SizedBox(height: 8),
            TextField(controller: fallbackKey, enabled: !busy, obscureText: true,
              autocorrect: false, enableSuggestions: false,
              onChanged: (_) => setState(() => fallbackConsent = false),
              decoration: const InputDecoration(
                labelText: 'Separate fallback API key (session only)',
                border: OutlineInputBorder())),
          ],
          OutlinedButton.icon(
            onPressed: busy || fallbackEndpoint == null ? null : () => _discover(fallback: true),
            icon: const Icon(Icons.manage_search),
            label: const Text('Fetch fallback model IDs'),
          ),
          CheckboxListTile(
            value: fallbackConsent,
            title: Text('I allow sending this same prompt to '
                '${fallbackEndpoint?.name ?? 'the selected fallback'} if needed'),
            onChanged: busy || fallbackEndpoint == null ? null : (value) =>
                setState(() => fallbackConsent = value ?? false),
          ),
        ],
        const SizedBox(height: 14),
        if (!consentToSendCode)
          const Text('Review your prompt and tick consent above to enable Send.'),
        FilledButton.icon(
          onPressed: busy || !consentToSendCode ||
              (allowFallback && !fallbackConsent) ? null : _send,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send),
          label: Text(busy ? 'Waiting for provider...' : 'Send to selected provider'),
        ),
        const SizedBox(height: 14),
        if (output.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(output),
            ),
          ),
        const SizedBox(height: 14),
        const StatusPill(
          label: 'Session keys only · reviewed local retrieval and analysis',
          icon: Icons.info_outline,
        ),
      ],
    );
  }
}

class _AiModelPicker extends StatefulWidget {
  const _AiModelPicker({required this.provider, required this.models});
  final String provider;
  final List<String> models;

  @override
  State<_AiModelPicker> createState() => _AiModelPickerState();
}

class _AiModelPickerState extends State<_AiModelPicker> {
  String filter = '';

  @override
  Widget build(BuildContext context) {
    final matches = widget.models.where((model) =>
        model.toLowerCase().contains(filter.toLowerCase())).toList();
    return AlertDialog(
      title: Text('${widget.provider} models'),
      content: SizedBox(
        width: 560,
        height: MediaQuery.sizeOf(context).height * 0.45,
        child: Column(
          children: [
            const Text('First catalog response, at most 1,000 IDs. '
                'Listing does not guarantee chat compatibility, access or free use.'),
            TextField(
              onChanged: (value) => setState(() => filter = value),
              decoration: const InputDecoration(labelText: 'Search model ID'),
            ),
            Expanded(child: ListView.builder(
              itemCount: matches.length,
              itemBuilder: (context, index) => ListTile(
                title: Text(matches[index]),
                onTap: () => Navigator.pop(context, matches[index]),
              ),
            )),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
      ],
    );
  }
}

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({
    super.key,
    required this.onImport,
    required this.onAnalyze,
    required this.controller,
    this.report,
  });

  final StudioController controller;
  final VoidCallback onImport;
  final VoidCallback onAnalyze;
  final ApkReport? report;

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  bool exporting = false;
  String exportStatus = '';
  final recoveryCursor = TextEditingController(text: '0:0:0');

  @override
  void didUpdateWidget(covariant ToolsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report?.id != widget.report?.id) {
      recoveryCursor.text = '0:0:0';
      exportStatus = '';
    }
  }

  @override
  void dispose() {
    recoveryCursor.dispose();
    super.dispose();
  }

  Future<void> _exportSourcePreview() async {
    final selected = widget.report;
    if (selected == null || exporting) {
      return;
    }
    setState(() {
      exporting = true;
      exportStatus = '';
    });
    try {
      final cursor = SourceRecoveryCursor.parse(recoveryCursor.text);
      final bundle = await SourceRecoveryBundle.fromProject(selected, cursor: cursor);
      if (!mounted || widget.report?.id != selected.id) {
        return;
      }
      final cleanName = selected.packageLabel
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final name = cleanName.length > 48
          ? cleanName.substring(0, 48) : cleanName;
      final filename = '${name.isEmpty ? 'recovered-app' : name}'
          '-source-preview-${cursor.dexIndex + 1}-'
          '${cursor.classIndex + 1}-${cursor.methodIndex + 1}.zip';
      final saved = await LocalExportService.saveFile(
        dialogTitle: 'Save read-only source recovery bundle',
        fileName: filename,
        bytes: bundle.zipBytes,
      );
      if (!mounted || widget.report?.id != selected.id) {
        return;
      }
      if (saved == null) {
        setState(() => exportStatus = 'Export cancelled');
      } else {
        setState(() {
          final next = bundle.nextCursor;
          if (next != null) {
            recoveryCursor.text = next.token;
          }
          exportStatus =
              'Saved $filename · ${bundle.dexFilesVisited} DEX files, '
              '${bundle.classesExported} classes, '
              '${bundle.methodsExported} methods'
              '${bundle.partial ? ' · PARTIAL (see REPORT.json)' : ''}'
              '${next == null ? ' · No further window' :
                  ' · Next: ${next.token}. Export again to continue.'}';
        });
      }
    } catch (error) {
      if (mounted && widget.report?.id == selected.id) {
        setState(() => exportStatus = 'Source export failed: $error');
      }
    } finally {
      if (mounted) {
        setState(() => exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const planned = <(IconData, String, String)>[
      (Icons.computer, 'Full multi-architecture ELF disassembler', 'Native engine phase'),
      (Icons.draw_outlined, 'On-device signing / full rebuild', 'Authorized edit phase'),
      (Icons.smart_toy_outlined, 'Expanded AI runtime integration', 'Optional external model validation'),
    ];
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('Tools and Workflows',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.file_open),
            title: const Text('Import an APK'),
            subtitle: const Text('Working: read-only local archive and '
                'manifest analysis'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onImport,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.inventory),
            title: const Text('Open APK Inspector'),
            subtitle: const Text('Working: files, permissions, DEX and '
                '.so inventory'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onAnalyze,
          ),
        ),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.edit),
          title: const Text('APK Asset Editor'),
          subtitle: const Text('Edit an existing text asset and export an unsigned APK copy'),
          trailing: const Icon(Icons.chevron_right),
          onTap: widget.report == null ? null : () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => ApkAssetEditorScreen(report: widget.report!)),
          ),
        )),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.account_tree_outlined),
          title: const Text('Smali & Resource Workspace'),
          subtitle: const Text('Windows only · trusted external Java / Apktool required'),
          onTap: !Platform.isWindows || widget.report == null ||
              !widget.report!.fileName.toLowerCase().endsWith('.apk') ? null : () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
                ApktoolWorkspaceScreen(report: widget.report!))),
        )),
        for (final comparison in [false, true])
          Card(child: ListTile(
            leading: Icon(comparison ? Icons.compare_arrows : Icons.fact_check_outlined),
            title: Text(comparison ? 'APK Version Diff' : 'APK Security Review'),
            subtitle: Text(comparison ? 'Compare imported APK member hashes' : 'Permissions and unverified signature structure'),
            onTap: widget.report == null || !widget.report!.fileName.toLowerCase().endsWith('.apk')
                ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
                    ApkSecurityScreen(active: widget.report!, projects: widget.controller.projects,
                        comparison: comparison))),
          )),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.code),
          title: const Text('JADX Java Source Recovery'),
          subtitle: const Text('Windows · external trusted JADX distribution'),
          onTap: !Platform.isWindows || widget.report == null ||
              !widget.report!.fileName.toLowerCase().endsWith('.apk') ? null : () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
                JadxRecoveryScreen(report: widget.report!))),
        )),
        Card(child: ListTile(
          leading: const Icon(Icons.account_tree),
          title: const Text('Framework Recovery Index'),
          subtitle: const Text('Local DEX, Flutter, React Native, Unity and NativeScript hints'),
          onTap: widget.report == null ? null : () {
            final index = FrameworkRecoveryIndex.build(widget.report!);
            final text = const JsonEncoder.withIndent('  ').convert(index);
            showDialog<void>(context: context, builder: (context) => AlertDialog(
              title: const Text('Framework evidence'),
              content: SizedBox(width: 660, height: MediaQuery.sizeOf(context).height * 0.55,
                child: SingleChildScrollView(child: SelectableText(text))),
              actions: [
                TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: text)),
                  child: const Text('Copy JSON')),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ],
            ));
          },
        )),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.usb),
          title: const Text('ADB Device Inspector'),
          subtitle: const Text('Windows · authorized device and selected app logs'),
          onTap: Platform.isWindows ? () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AdbDeviceScreen())) : null,
        )),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.layers_outlined),
          title: const Text('Framework Binary Inspector'),
          subtitle: const Text('Hermes · Unity metadata · React Native · NativeScript'),
          onTap: widget.report == null ? null : () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => FrameworkBinaryScreen(report: widget.report!))),
        )),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.memory),
          title: const Text('Universal Binary Inspector'),
          subtitle: const Text('PE / ELF header, hex pages and binary search'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const UniversalBinaryScreen())),
        )),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.dashboard_customize_outlined),
          title: const Text('Universal Project Workspace'),
          subtitle: const Text('File tree · tabs · source drafts · local search'),
          onTap: !Platform.isWindows && widget.report?.recoveredFolderUri == null &&
              widget.report?.recoveredFolderPath == null ? null : () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
                ProjectWorkspaceScreen(folderPath: widget.report?.recoveredFolderPath,
                  folderUri: widget.report?.recoveredFolderUri))),
        )),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: const Text('Split APK & Framework Member Export'),
          subtitle: const Text('Extract individual APK, Hermes, Unity or NativeScript members'),
          onTap: widget.report == null ? null : () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => ArchiveMemberExportScreen(report: widget.report!))),
        )),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.storage),
          title: const Text('Large Binary Viewer'),
          subtitle: const Text('Streaming hex pages, hash and search up to 1 GiB'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const PagedBinaryScreen())),
        )),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.account_tree_outlined),
          title: const Text('Ghidra Native Decompiler'),
          subtitle: const Text('Windows · external Ghidra / JDK · function calls and pseudocode'),
          onTap: !Platform.isWindows ? null : () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const GhidraHeadlessScreen())),
        )),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.fact_check_outlined),
          title: const Text('Split APK Set Preflight'),
          subtitle: const Text('Manifest identity and split consistency'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const SplitSetScreen())),
        )),
        Card(child: ListTile(
          leading: const Icon(Icons.build_circle_outlined),
          title: const Text('Universal Tool Manager'),
          subtitle: const Text('Windows · detect and validate external tool versions'),
          onTap: !Platform.isWindows ? null : () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ExternalToolManagerScreen())),
        )),
        Text('Source Recovery — paged export',
            style: Theme.of(context).textTheme.titleMedium),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Offline Source Recovery Preview ZIP',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 5),
                Text(widget.report == null
                    ? 'Import an APK first to enable this feature.'
                    : 'Selected APK: ${widget.report!.fileName}'),
                const SizedBox(height: 6),
                if (widget.controller.desktopRecovery)
                  const Text('Choose a desktop folder for generated previews, or use local app storage. Existing folders are not overwritten.')
                else const Text('After APK import, choose a writable folder in '
                    'the Android system file picker. DroidRE creates the '
                    'reconstructed project there, outside Android/data, '
                    'with technology-aware notes, Java-like text, Dalvik '
                    'reports and resource previews. Output is not original '
                    'or compilable source.'),
                const SizedBox(height: 10),
                Text(widget.controller.recoveryDestinationLabel == null
                    ? 'No custom recovery folder selected.'
                    : 'Destination: ${widget.controller.recoveryDestinationLabel}'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: widget.controller.busy
                      ? null : () async {
                          await widget.controller.chooseRecoveryDestination();
                        },
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: Text(widget.controller.desktopRecovery
                      ? 'Choose desktop output folder' : 'Choose File Manager Folder'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: widget.report == null || widget.controller.busy
                      ? null : () async {
                          await widget.controller.generateInSelectedFolder();
                        },
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: const Text('Generate Code in Selected Folder'),
                ),
                const SizedBox(height: 8),
                if (!widget.controller.desktopRecovery) const Text('Android 11+ restricts selecting storage roots '
                    'and the Downloads root. Choose Documents or another '
                    'writable subfolder. Existing generated project folders '
                    'will never be overwritten.'),
                const SizedBox(height: 12),
                TextField(
                  controller: recoveryCursor,
                  enabled: widget.report != null && !exporting,
                  decoration: const InputDecoration(
                    labelText: 'Recovery cursor (DEX:class:method)',
                    helperText: 'Zero-based. Next cursor fills after saving a ZIP.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: widget.report == null || exporting
                      ? null : _exportSourcePreview,
                  icon: exporting
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_zip_outlined),
                  label: Text(exporting
                      ? 'Recovering locally...' : 'Export Source Preview ZIP'),
                ),
                if (widget.report?.recoveredFolderUri != null ||
                    widget.report?.recoveredFolderPath != null) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const Text('Generated project location:'),
                  const SizedBox(height: 4),
                  SelectableText(widget.report!.recoveredFolderLabel ??
                      widget.report!.recoveredFolderPath ??
                      'User-selected document folder',
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12)),
                  const SizedBox(height: 8),
                  Text('${widget.report!.recoveredFileCount} generated files'
                      '${widget.report!.recoveryPartial ? ' · partial' : ''}'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RecoveredFolderBrowserScreen(
                          folderPath: widget.report!.recoveredFolderUri != null
                              ? null : widget.report!.recoveredFolderPath,
                          folderUri: widget.report!.recoveredFolderUri,
                          folderLabel: widget.report!.recoveredFolderLabel,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Browse Generated Code'),
                  ),
                ],
                if (exportStatus.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SelectableText(exportStatus),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text('Roadmap — not implemented yet',
            style: Theme.of(context).textTheme.titleMedium),
        for (final tool in planned)
          Card(
            child: ListTile(
              leading: Icon(tool.$1),
              title: Text(tool.$2),
              subtitle: Text(tool.$3),
              trailing: const Icon(Icons.schedule),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${tool.$2}: ${tool.$3}')),
              ),
            ),
          ),
      ],
    );
  }
}

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final account = GoogleAccountService.instance;
  late final TextEditingController clientIdController;
  String message = '';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    clientIdController = TextEditingController(text: account.webClientId);
    account.addListener(_onAccountChanged);
    _loadAccount();
  }

  void _onAccountChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAccount() async {
    try {
      await account.loadConfiguration();
      if (!mounted) return;
      clientIdController.text = account.webClientId;
      if (account.supported && account.configured && !account.requiresRestart) {
        await account.restoreSession();
      }
    } catch (error) {
      if (mounted) {
        setState(() => message = 'Account restore unavailable: $error');
      }
    }
  }

  Future<void> _saveClientId() async {
    setState(() => busy = true);
    try {
      await account.saveClientId(clientIdController.text);
      if (mounted) {
        setState(() => message = account.requiresRestart
            ? 'Saved. Restart the app before signing in with this new ID.'
            : 'Web OAuth Client ID saved on this device.');
      }
    } catch (error) {
      if (mounted) setState(() => message = 'Could not save OAuth ID: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    account.removeListener(_onAccountChanged);
    clientIdController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() => busy = true);
    try {
      final profile = await account.signIn();
      if (mounted) setState(() => message = 'Signed in as ${profile.email}');
    } catch (error) {
      if (mounted) setState(() => message = 'Google sign-in failed: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account & Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Google account', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (!account.supported)
            const Text('Google sign-in is not implemented on Windows/Linux. Local projects and AI Studio work without an account.')
          else ...[
          Text(account.configured
              ? 'Web OAuth Client ID is configured. Android package and signing '
                  'fingerprint must also be registered with Google Cloud.'
              : 'Google identity sign-in requires your registered Web OAuth '
                  'Client ID. Enter it below and save it on this device.'),
          const SizedBox(height: 14),
          TextField(
            controller: clientIdController,
            decoration: const InputDecoration(
              labelText: 'Google Web OAuth Client ID',
              hintText: '12345-abc.apps.googleusercontent.com',
              border: OutlineInputBorder(),
              helperText: 'Public OAuth client ID, not a client secret.',
            ),
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy ? null : _saveClientId,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save OAuth configuration'),
          ),
          const SizedBox(height: 8),
          const SelectableText('Android package: com.jahid.droidreai'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy || !account.configured || account.requiresRestart
                ? null : _signIn,
            icon: const Icon(Icons.account_circle),
            label: const Text('Continue with Google'),
          ),
          if (account.account != null)
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: Text(account.account!.displayName ?? 'Google account'),
              subtitle: Text(account.account!.email),
            ),
          if (account.account != null)
            TextButton(
              onPressed: () async {
                await account.signOut();
                if (mounted) setState(() => message = 'Signed out');
              },
              child: const Text('Sign out'),
            ),
          ],
          if (message.isNotEmpty) Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(message),
          ),
          const Divider(height: 36),
          Text('Privacy & capabilities', style: Theme.of(context).textTheme.titleLarge),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Local-first'),
            subtitle: Text('Your imported APK files stay on this device'),
          ),
          const ListTile(
            leading: Icon(Icons.key_off_outlined),
            title: Text('API keys are not saved'),
            subtitle: Text('AI keys exist in memory only during the current session'),
          ),
          const ListTile(
            leading: Icon(Icons.build_circle_outlined),
            title: Text('Version 0.9.0 — Preview'),
            subtitle: Text('See docs/FEATURE_STATUS.md for engine limitations'),
          ),
        ],
      ),
    );
  }
}
