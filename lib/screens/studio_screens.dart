import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../models/apk_report.dart';
import '../services/ai_chat_service.dart';
import '../services/google_account_service.dart';
import '../services/studio_controller.dart';
import '../services/source_recovery_bundle.dart';
import 'binary_explorer_tabs.dart';
import 'resource_explorer_tab.dart';
import 'recovered_folder_browser.dart';

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
        final wide = MediaQuery.sizeOf(context).width >= 850;
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
          ),
          ToolsScreen(
            controller: widget.controller,
            report: widget.controller.active,
            onImport: _import,
            onAnalyze: () => setState(() => _tab = 2),
          ),
        ];
        return Scaffold(
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
                  labelType: NavigationRailLabelType.all,
                  destinations: List.generate(
                    _titles.length,
                    (index) => NavigationRailDestination(
                      icon: Icon(_icons[index]),
                      selectedIcon: Icon(_selectedIcons[index]),
                      label: Text(_titles[index]),
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
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
        );
      },
    );
  }
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
  const AiStudioScreen({super.key, this.initialPrompt = ''});

  final String initialPrompt;

  @override
  State<AiStudioScreen> createState() => _AiStudioScreenState();
}

class _AiStudioScreenState extends State<AiStudioScreen> {
  final keyController = TextEditingController();
  final modelController = TextEditingController(text: aiEndpoints.first.defaultModel);
  late final TextEditingController promptController;
  final service = AiChatService();
  AiEndpoint endpoint = aiEndpoints.first;
  String output = '';
  bool busy = false;
  bool consentToSendCode = false;

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
    service.close();
    super.dispose();
  }

  Future<void> _send() async {
    if (busy || (widget.initialPrompt.isNotEmpty && !consentToSendCode)) return;
    setState(() {
      busy = true;
      output = '';
    });
    try {
      final response = await service.complete(
        endpoint: endpoint,
        model: modelController.text,
        apiKey: keyController.text,
        prompt: promptController.text,
      );
      if (mounted) setState(() => output = response);
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
        const SizedBox(height: 18),
        DropdownButtonFormField<AiEndpoint>(
          initialValue: endpoint,
          decoration: const InputDecoration(
            labelText: 'AI Provider',
            border: OutlineInputBorder(),
          ),
          items: aiEndpoints.map(
            (item) => DropdownMenuItem(value: item, child: Text(item.name)),
          ).toList(),
          onChanged: busy
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() {
                    endpoint = value;
                    modelController.text = value.defaultModel;
                  });
                },
        ),
        const SizedBox(height: 10),
        Text(endpoint.description),
        const SizedBox(height: 12),
        TextField(
          controller: modelController,
          decoration: const InputDecoration(
            labelText: 'Model ID',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: keyController,
          obscureText: true,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'API key (session only)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.key),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: promptController,
          minLines: 4,
          maxLines: 9,
          decoration: const InputDecoration(
            labelText: 'Ask about Android code',
            hintText: 'Paste the code or manifest snippet you want explained...',
            border: OutlineInputBorder(),
          ),
        ),
        if (widget.initialPrompt.isNotEmpty)
          CheckboxListTile(
            value: consentToSendCode,
            title: const Text('I reviewed the extracted code and agree to '
                'send this text to the selected AI provider'),
            subtitle: const Text('Check for embedded secrets first. '
                'The APK file itself stays on this device.'),
            onChanged: busy ? null : (value) => setState(() =>
                consentToSendCode = value ?? false),
          ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: busy ||
              (widget.initialPrompt.isNotEmpty && !consentToSendCode)
              ? null : _send,
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
          label: 'Automatic fallback / local RAG: later milestones',
          icon: Icons.info_outline,
        ),
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
      final saved = await FilePicker.platform.saveFile(
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
      (Icons.account_tree_outlined, 'Smali editor', 'Native engine phase'),
      (Icons.computer, 'ELF disassembler', 'Native engine phase'),
      (Icons.compare_arrows, 'Version diff', 'Planned'),
      (Icons.fact_check_outlined, 'Security audit', 'Planned'),
      (Icons.draw_outlined, 'Rebuild and sign', 'Authorized edit phase'),
      (Icons.smart_toy_outlined, 'Local AI', 'Optional model phase'),
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
                const Text('After APK import, choose a writable folder in '
                    'the Android system file picker. DroidRE creates the '
                    'reconstructed project there, outside Android/data, '
                    'with technology-aware notes, Java-like text, Dalvik '
                    'reports and resource previews. Output is not original '
                    'or compilable source.'),
                const SizedBox(height: 10),
                Text(widget.controller.sourceDestination == null
                    ? 'No public recovery folder selected.'
                    : 'Destination: ${widget.controller.sourceDestination!.label}'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: widget.controller.busy
                      ? null : () async {
                          await widget.controller.chooseRecoveryDestination();
                        },
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Choose File Manager Folder'),
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
                const Text('Android 11+ restricts selecting storage roots '
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
      if (account.configured && !account.requiresRestart) {
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
            title: Text('Version 0.6.0 — Reverse Engineering Studio'),
            subtitle: Text('See docs/FEATURE_STATUS.md for engine limitations'),
          ),
        ],
      ),
    );
  }
}
